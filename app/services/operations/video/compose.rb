# frozen_string_literal: true

require 'open-uri'

module Operations
  module Video
    # Composes the final video: ffmpeg-concats the creative's ready scene clips
    # into one MP4, attaches it, and finalizes the generation (ready + cost +
    # credit reconciliation + broadcast + notify). Idempotent — a completed
    # generation short-circuits. Runs from a job, so it resolves the tenant from
    # the records, never from Current.
    class Compose < Operations::Base
      ASPECT_DIMENSIONS = {
        '9:16' => [1080, 1920], '1:1' => [1080, 1080],
        '16:9' => [1920, 1080], '4:5' => [1080, 1350]
      }.freeze

      # remix: re-burn the audio (e.g. a changed music track) over the already
      # composed video WITHOUT re-finalizing (no credit reconcile, no notify) —
      # runs even when the generation is already completed.
      def initialize(creative:, remix: false)
        @creative = creative
        @remix    = remix
      end

      def call
        generation = @creative.generation
        return @creative if !@remix && generation&.status_completed?

        scenes = @creative.video_scenes.ordered.select(&:composable?)
        return @creative if scenes.empty?

        attach_composed!(scenes)
        return remix_broadcast!(generation) if @remix

        @creative.update!(status: :ready, metadata: @creative.metadata.merge('scene_count' => scenes.size))
        finalize_generation!(generation, scenes) if generation
        broadcast!(generation)
        @creative
      end

      private

      def attach_composed!(scenes)
        Dir.mktmpdir('hf-compose') do |dir|
          inputs = scenes.each_with_index.map { |s, i| download(s, File.join(dir, "s#{i}.mp4")) }
          w, h = dimensions
          out = File.join(dir, 'final.mp4')
          # When a FIXED voice was synthesized, DUB it in: the model's audio is
          # dropped (it drifts the voice between clips + adds its own music) and
          # each scene's Cartesia voice clip is laid at its offset, with the
          # music burned under it — one consistent voice, music only from post.
          # No voice ⇒ keep the model's native audio + burn the music under it.
          voices = with_audio? ? voice_paths(scenes, dir) : []
          Vendors::Ffmpeg::Concat.call(input_paths: inputs, width: w, height: h, output_path: out,
                                       mute: !with_audio?, music_path: music_path(dir),
                                       music_mix: music_mix, voice_paths: voices)

          @creative.assets.purge if @creative.assets.attached?
          @creative.assets.attach(io: File.open(out), filename: "video-#{@creative.id}.mp4", content_type: 'video/mp4')
        end
      end

      # The synthesized fixed-voice clip per scene (nil where none), parallel to
      # the input clips — the dub inputs for Concat. Empty when no scene has one.
      def voice_paths(scenes, dir)
        paths = scenes.each_with_index.map do |s, i|
          next nil unless s.voice_clip.attached?

          p = File.join(dir, "voice#{i}.mp3")
          s.voice_clip.open { |tmp| FileUtils.cp(tmp.path, p) }
          p
        rescue StandardError => e
          Rails.logger.warn("[Video::Compose] voice clip #{s.id} unavailable: #{e.message}")
          nil
        end
        paths.any? ? paths : []
      end

      # A remix only swapped the soundtrack — nudge the UI to reload the asset,
      # no status change, no cost, no notification.
      def remix_broadcast!(generation)
        Broadcaster.ticket(@creative.ticket, 'creative_ready', creative_id: @creative.id) if @creative.ticket
        if generation
          Broadcaster.generations(generation.workspace_id, 'generation_progress',
                                  id: generation.id, kind: 'video', status: 'processing')
        end
        @creative
      rescue NameError
        @creative
      end

      def download(scene, path)
        scene.clip.open { |tmp| FileUtils.cp(tmp.path, path) }
        path
      end

      # Download the selected royalty-free track (best-effort). No URL, a silent
      # video, or a fetch error → no music (the video ships anyway).
      def music_path(dir)
        return nil unless with_audio?

        url = @creative.generation&.params&.dig('music_url')
        return nil if url.blank?

        path = File.join(dir, 'music')
        URI.parse(url).open { |io| File.binwrite(path, io.read) }
        path
      rescue StandardError => e
        Rails.logger.warn("[Video::Compose] music download failed (#{url}): #{e.message}")
        nil
      end

      # The orchestrator's ffmpeg mix knobs, stored on the generation.
      def music_mix
        p = @creative.generation&.params || {}
        { volume: p['music_volume'], fade_in: p['music_fade_in'],
          fade_out: p['music_fade_out'], duck: p['music_duck'] }.compact
      end

      def dimensions
        aspect = @creative.video_scenes.first&.aspect_ratio.presence ||
                 @creative.generation&.params&.dig('aspect_ratio')
        ASPECT_DIMENSIONS.fetch(aspect, ASPECT_DIMENSIONS['9:16'])
      end

      # Sound is ON by default; only a generation that explicitly opted out
      # (with_audio: false) is muted at compose.
      def with_audio?
        meta = @creative.metadata || {}
        gen  = @creative.generation&.params || {}
        val = meta.key?('with_audio') ? meta['with_audio'] : gen['with_audio']
        val.nil? ? true : ActiveModel::Type::Boolean.new.cast(val)
      end

      # --- finalize the generation --------------------------------------------

      def finalize_generation!(generation, scenes)
        total_seconds = scenes.sum { |s| s.duration_seconds.to_i }
        cost = scenes.sum { |s| s.cost_cents.to_i }
        generation.update!(
          status: :completed,
          cost_cents: cost.positive? ? cost : generation.cost_cents,
          result: generation.result.merge('duration' => total_seconds, 'scene_count' => scenes.size)
        )
        reconcile_credits!(generation, total_seconds, cost)
        log_cost!(generation, total_seconds, cost)
      end

      # True-up an up-front ESTIMATE HOLD to the real total duration. Only two
      # debits are holds: the generation's FIRST debit (the initial estimate)
      # and the high-quality upgrade hold. Per-scene edit debits are already
      # exact — reconciling against them would re-charge the whole video on
      # every recompose after an edit.
      def reconcile_credits!(generation, total_seconds, cost)
        # True-up to the REAL summed scene cost; fall back to the seconds estimate
        # if the vendor reported no cost, so a render is never trued-up to zero.
        actual = if cost.to_i.positive?
                   Pricing.credits_for_cost(cost_cents: cost)
                 else
                   Pricing.credits_for(kind: :video, seconds: total_seconds)
                 end
        debits = generation.workspace.credit_transactions.debits
                           .where(generation_id: generation.id).order(:created_at).to_a
        debit = debits.last
        return unless debit
        return unless debit.id == debits.first.id || debit.description == UpgradeQuality::HOLD_DESCRIPTION

        delta = (-debit.amount) - actual
        return if delta.zero?

        Operations::Credits::Adjust.call(
          workspace: generation.workspace, amount: delta, generation: generation,
          description: "Ajuste de créditos do vídeo (#{total_seconds}s)"
        )
      end

      def log_cost!(generation, total_seconds, cost)
        Operations::Ai::LogUsage.call(
          provider: AiUsageLog::PROVIDER_OPENROUTER, operation: 'generate_video',
          model: VideoConfig.instance.model_for(generation.params['mode'],
                                                quality: generation.params['quality'].presence || 'final'),
          units: total_seconds, unit_kind: AiUsageLog::UNIT_SECOND,
          cost_cents: cost.positive? ? cost : nil,
          subject: generation, workspace: generation.workspace, user: generation.user
        )
      end

      def broadcast!(generation)
        Broadcaster.ticket(@creative.ticket, 'creative_ready', creative_id: @creative.id) if @creative.ticket
        return unless generation

        Broadcaster.generations(generation.workspace_id, 'generation_done',
                                id: generation.id, kind: 'video', status: 'completed')
        notify_owner(generation)
        Operations::Autopilot::OnGenerationSettled.call(generation: generation)
      rescue NameError
        nil
      end

      def notify_owner(generation)
        Operations::Push::Notify.call(
          user: generation.user, title: 'Vídeo pronto ✨',
          body: 'Sua geração foi concluída e já está disponível.',
          path: @creative.ticket ? "/tickets/#{@creative.ticket_id}" : '/estudio'
        )
        return if generation.user&.email.blank?

        CreativeMailer.ready(generation: generation, user: generation.user).deliver_later
      end
    end
  end
end
