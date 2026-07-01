# frozen_string_literal: true

require "open-uri"

module Operations
  module Creatives
    # Finalizes an async generation once the vendor has produced the asset.
    #
    # Called by the webhook fast path (`Controllers::Webhooks::Heygen`) and by the
    # `PollHeygenVideoJob` safety net. Downloads the produced MP4/image (vendor
    # URLs are presigned + expire), attaches it to the Creative's `assets`
    # (ActiveStorage), marks the Creative `ready` + the Generation `completed`,
    # computes `cost_cents`, meters billable kinds via Operations::Billing::
    # RecordUsage (if defined), and broadcasts `creative_ready` / `generation_done`.
    #
    # Runs outside a request, so it resolves the tenant from the Generation, not
    # from Current. Idempotent: a completed Generation short-circuits.
    class FinalizeGeneration < Operations::Base
      # Per-second HeyGen rates by engine (USD). Standard avatar ≈ $1/min.
      # See docs/integrations/heygen.md §6.
      HEYGEN_RATE_CENTS_PER_SECOND = {
        "avatar" => 1.667,    # ~$1.00/min standard avatar video
        "avatar_iv" => 5.0,   # $0.05/sec Avatar IV
        "avatar_iii" => 4.33  # $0.0433/sec Avatar III photo avatar
      }.freeze
      DEFAULT_HEYGEN_RATE_CENTS_PER_SECOND = HEYGEN_RATE_CENTS_PER_SECOND.fetch("avatar")

      def initialize(generation:, video_url: nil, image_url: nil, duration: nil, metadata: {})
        @generation = generation
        @video_url  = video_url
        @image_url  = image_url
        @duration   = duration
        @metadata   = metadata || {}
      end

      def call
        return @generation if @generation.status_completed?

        creative = @generation.creative
        url = @video_url || @image_url
        attach!(creative, url) if creative && url.present?

        cost_cents = compute_cost_cents

        creative&.update!(
          status: :ready,
          metadata: creative.metadata.merge(finalize_metadata(url))
        )

        @generation.update!(
          status: :completed,
          cost_cents: cost_cents,
          result: @generation.result.merge(result_payload(url))
        )

        reconcile_credits!
        log_ai_cost!(cost_cents)
        broadcast!(creative)

        @generation
      end

      private

      # --- asset download + attach --------------------------------------------

      def attach!(creative, url)
        filename, content_type = file_meta(url)
        downloaded = URI.parse(url).open

        creative.assets.attach(
          io: downloaded,
          filename: filename,
          content_type: content_type
        )
      ensure
        downloaded&.close if defined?(downloaded) && downloaded.respond_to?(:close)
      end

      def file_meta(url)
        if @video_url.present?
          ["#{@generation.external_id || @generation.id}.mp4", "video/mp4"]
        else
          ext = File.extname(URI.parse(url).path).presence || ".png"
          content_type = ext == ".jpg" || ext == ".jpeg" ? "image/jpeg" : "image/png"
          ["#{@generation.external_id || @generation.id}#{ext}", content_type]
        end
      rescue URI::InvalidURIError
        ["#{@generation.id}.bin", "application/octet-stream"]
      end

      # --- cost ----------------------------------------------------------------

      def compute_cost_cents
        return @generation.cost_cents if @generation.cost_cents.present?

        case @generation.kind
        when "video"
          duration = (@duration || @generation.result["duration"] || @generation.params["duration"]).to_f
          rate = HEYGEN_RATE_CENTS_PER_SECOND[engine] || DEFAULT_HEYGEN_RATE_CENTS_PER_SECOND
          (duration * rate).round
        else
          @generation.cost_cents
        end
      end

      def engine
        (@metadata[:engine] || @generation.params["engine"] || "avatar").to_s
      end

      # --- credits -------------------------------------------------------------

      # True-up the up-front credit hold (a 30s standard-avatar estimate) to the
      # real duration + engine now that the render is done. Refunds the difference
      # if the video came out shorter, charges the difference (best-effort) if
      # longer/photoreal. Images/carousels were charged exactly — nothing to do.
      def reconcile_credits!
        return unless @generation.kind == "video"

        actual = Pricing.credits_for(kind: :video, seconds: video_seconds, engine: engine)
        debit = @generation.workspace.credit_transactions
                           .debits.where(generation_id: @generation.id).order(:created_at).last
        return unless debit

        charged = -debit.amount
        delta = charged - actual # >0 ⇒ refund overcharge, <0 ⇒ charge more
        return if delta.zero?

        Operations::Credits::Adjust.call(
          workspace:  @generation.workspace,
          amount:     delta,
          generation: @generation,
          description: "Ajuste de créditos do vídeo (#{video_seconds.round}s)"
        )
      end

      def video_seconds
        (@duration || @generation.result["duration"] || @generation.params["duration"] ||
          Pricing::DEFAULT_VIDEO_SECONDS).to_f
      end

      # --- billing -------------------------------------------------------------

      # Record the internal AI vendor cost (HeyGen, per-second) in the unified
      # ledger. Engine-specific rate is already folded into cost_cents, so pass it
      # explicitly. Runs outside a request — resolve tenant from the Generation.
      def log_ai_cost!(cost_cents)
        return unless @generation.kind == "video"

        duration = (@duration || @generation.result["duration"] || @generation.params["duration"]).to_f
        Operations::Ai::LogUsage.call(
          provider:   AiUsageLog::PROVIDER_HEYGEN,
          operation:  "generate_ugc_video",
          model:      engine,
          units:      duration,
          unit_kind:  AiUsageLog::UNIT_SECOND,
          cost_cents: cost_cents,
          subject:    @generation,
          workspace:  @generation.workspace,
          user:       @generation.user
        )
      end

      # NOTE: post-paid Stripe usage metering was removed in favour of the prepaid
      # credit wallet (Operations::Credits::*). Generation is now charged in
      # credits at request time (debited in the generation op, reconciled here in
      # `reconcile_credits!`), so there is no Stripe meter event to emit.

      # --- broadcasts ----------------------------------------------------------

      def broadcast!(creative)
        if creative&.ticket
          Broadcaster.ticket(creative.ticket, "creative_ready", creative_id: creative.id, generation_id: @generation.id)
        end
        Broadcaster.generations(
          @generation.workspace_id,
          "generation_done",
          id: @generation.id, kind: @generation.kind, status: "completed"
        )
        notify_owner(creative)
      end

      # Tell whoever requested the generation that their creative is ready (no
      # actor exclusion — they want the completion notice even if they started it).
      def notify_owner(creative)
        kind_label = { "carousel" => "Carrossel", "video" => "Vídeo", "image" => "Imagem" }[@generation.kind.to_s] || "Criativo"
        Operations::Push::Notify.call(
          user: @generation.user,
          title: "#{kind_label} pronto ✨",
          body: "Sua geração foi concluída e já está disponível.",
          path: creative&.ticket ? "/tickets/#{creative.ticket_id}" : "/estudio"
        )

        owner = @generation.user
        return if owner.nil? || owner.email.blank?

        CreativeMailer.ready(generation: @generation, user: owner).deliver_later
      end

      # --- payloads ------------------------------------------------------------

      def finalize_metadata(url)
        meta = {}
        meta[:video_url] = url if @video_url.present?
        meta[:image_url] = url if @image_url.present?
        meta.merge(@metadata.slice(:thumbnail_url, :gif_url, :duration, :engine))
      end

      def result_payload(url)
        payload = {}
        payload["video_url"] = url if @video_url.present?
        payload["image_url"] = url if @image_url.present?
        payload["duration"] = @duration if @duration
        payload.merge(@metadata.stringify_keys.slice("thumbnail_url", "gif_url"))
      end
    end
  end
end
