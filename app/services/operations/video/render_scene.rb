# frozen_string_literal: true

module Operations
  module Video
    # Submits ONE scene to OpenRouter (engine chosen by VideoConfig per mode),
    # marks it `rendering`, and enqueues the per-scene poll.
    #
    # CONTINUITY: a scene starts from the PREVIOUS scene's last frame (first-frame
    # conditioning) so the video flows without a jump-cut. A RE-RENDER of the
    # FIRST scene is conditioned on its own current opening frame instead
    # (keep-look), unless the edit asked for a restyle. The caller may pass an
    # explicit `first_frame_url` to override the derivation.
    class RenderScene < Operations::Base
      def initialize(scene:, first_frame_url: nil)
        @scene           = scene
        @first_frame_url = first_frame_url
      end

      def call
        seed = first_frame_seed
        kind = continuation_kind(seed)
        # A restyle or an intentional CUT deliberately breaks from the previous
        # frame, so a missing seed is expected there — only warn about an
        # UNINTENTIONAL continuity gap (a continuation that lost its seed).
        if seed.nil? && @scene.position.to_i.positive? && !restyle? && continues_previous?
          Rails.logger.warn("[Video::RenderScene] scene #{@scene.id} (pos #{@scene.position}) " \
                            'rendering WITHOUT a continuity seed — it will look like a new video')
        end
        prompt = render_prompt(continuation: kind)

        job_id = begin
          submit(prompt, seed && { url: seed[:primary], frame_type: 'first' })
        rescue StandardError
          # The API/engine may reject an inline data-URL frame — retry once with
          # the public URL before giving up (continuity beats failing the render).
          raise unless seed&.dig(:fallback)

          submit(prompt, { url: seed[:fallback], frame_type: 'first' })
        end

        @scene.update!(external_id: job_id, render_state: :rendering)
        PollVideoSceneJob.perform_later(@scene.id)
        @scene
      end

      private

      def submit(prompt, frame)
        Vendors::OpenRouter::Actions::GenerateVideo.call(
          mode: @scene.mode,
          model: VideoConfig.instance.model_for(@scene.mode, quality: quality),
          prompt: prompt,
          aspect_ratio: @scene.aspect_ratio,
          duration: @scene.duration_seconds,
          input_references: @scene.reference_urls.map { |url| { url: url } },
          frame_images: [frame].compact
        )
      end

      # The generation's quality tier (draft-first; 'final' after the upgrade).
      def quality
        @scene.creative.generation&.params&.fetch('quality', 'final') || 'final'
      end

      # The submitted prompt = the scene's CLEAN stored fields (visual prompt,
      # dialogue, on-screen text) compiled with the standing contracts
      # (continuity/reference manifest/style fence/audio/lettering). Compiling
      # at render time keeps chat edits covered and the stored fields lean.
      def render_prompt(continuation:)
        DecoratePrompt.call(
          prompt: @scene.prompt, mode: @scene.mode, ctx: ctx,
          continuation: continuation, with_audio: with_audio,
          dialogue: @scene.metadata['dialogue'],
          on_screen_text: @scene.metadata['on_screen_text'],
          voice_tone: voice_tone,
          guardrails: ctx.guardrails,
          reference_labels: reference_labels
        )
      end

      REFERENCE_ROLE_TEXT = {
        'logo' => 'the brand LOGO — context only: the scene does not need to show any logo; ' \
                  'if branding naturally appears, use EXACTLY this mark, never an invented or altered one',
        'avatar' => 'the CREATOR (the spokesperson) — the person on camera must faithfully match this face and appearance',
        'product' => 'product reference photo — keep the product faithful: exact shape, colors and label, never distorted',
        'reference' => 'a REFERENCE image the user attached (style / subject / scene guidance) — draw on it ' \
                       'for what the scene should look like; use it only where the prompt calls for it'
      }.freeze

      # Labels each attached reference image BY the ROLE captured at plan time, so
      # a changed brand asset or app host can never mislabel the logo/avatar as a
      # product photo (the old URL-equality bug).
      def reference_labels
        @scene.labeled_references.each_with_index.map do |ref, i|
          text = REFERENCE_ROLE_TEXT.fetch(ref[:role], REFERENCE_ROLE_TEXT['product'])
          "image #{i + 1}: #{text}"
        end
      end

      # The requested vocal delivery (avatar mode) → a delivery tone the model
      # applies to the spoken line. nil when no voice was chosen or sound is off.
      VOICE_TONES = {
        'pt_br_warm' => 'warm and friendly', 'pt_br_energetic' => 'energetic and upbeat',
        'pt_br_pro' => 'professional and confident'
      }.freeze

      def voice_tone
        return nil unless with_audio

        VOICE_TONES[@scene.creative.generation&.params&.dig('voice').to_s]
      end

      def restyle? = @scene.metadata['restyle'] == true

      # A scene continues the previous shot (seamless, seeded) unless the
      # storyboard marked it a CUT. Legacy scenes (nil) default to continue.
      def continues_previous? = @scene.metadata['continues_previous'] != false

      # What continuity directive the compiled prompt gets:
      #   :self   — a keep-look re-render seeded by the scene's own frame
      #   :previous — a seamless continuation seeded by the predecessor's frame
      #   :cut    — an intentional NEW shot (same world/characters, no seed)
      #   false   — the first scene, or an unseeded standalone
      def continuation_kind(seed)
        return seed[:kind] if seed
        return :cut if @scene.position.to_i.positive? && !restyle? && !continues_previous?

        false
      end

      # nil when the generation predates the flag — DecoratePrompt then skips
      # the audio directive.
      def with_audio
        params = @scene.creative.generation&.params
        return nil if params.nil? || !params.key?('with_audio')

        ActiveModel::Type::Boolean.new.cast(params['with_audio'])
      end

      # Same context shape StartRender plans with, rebuilt from the records (this
      # runs in jobs — never from Current). Memoized: several compile steps read it.
      def ctx
        @ctx ||= begin
          creative  = @scene.creative
          client_id = creative.generation&.params&.dig('client_id')
          ::Tickets::CreativeContext.for(
            creative.ticket,
            creative_type: creative.creative_type,
            client: client_id.present? ? @scene.workspace.clients.find_by(id: client_id) : nil
          )
        end
      end

      # The CONTINUITY SEED — the previous scene's final frame, the one thing
      # that makes scenes continue instead of coming out as N versions of the
      # same video. The frame is inlined as a data URL so the engine ALWAYS
      # receives the actual pixels: a public URL depends on the app host being
      # reachable from OpenRouter (rotated ngrok tunnels / interstitials break
      # conditioning silently). The public URL rides along as fallback.
      # Returns { primary:, fallback: } or nil (first scene / frame missing).
      MAX_INLINE_FRAME_BYTES = 4.megabytes

      def first_frame_seed
        return { primary: @first_frame_url, kind: :previous } if @first_frame_url.present?
        # A restyle breaks from the current look at ANY position — no seed and no
        # continuity directive, so the new look isn't fought by the old frame.
        return nil if restyle?
        # A CUT is a new shot in the same video — it must NOT start from the
        # previous frame (the scenario/framing differs), only the input_references
        # (the things used) carry over.
        return nil if @scene.position.to_i.positive? && !continues_previous?
        return own_first_frame_seed if @scene.position.to_i.zero?

        prev = @scene.creative.video_scenes.find_by(position: @scene.position - 1)
        frame = prev&.last_frame
        return nil unless frame&.attached?

        url = prev.last_frame_url
        return url.presence && { primary: url, kind: :previous } if frame.byte_size.to_i > MAX_INLINE_FRAME_BYTES

        data = "data:#{frame.content_type.presence || 'image/png'};base64,#{Base64.strict_encode64(frame.download)}"
        { primary: data, fallback: url.presence, kind: :previous }.compact
      rescue StandardError => e
        Rails.logger.warn("[Video::RenderScene] seed frame unavailable for scene #{@scene.id}: #{e.class}: #{e.message}")
        nil
      end

      # A RE-RENDER of the first scene keeps the look the user already saw by
      # conditioning on its own current opening frame — the "reference to the
      # last video". Skipped when the edit asked for a restyle (metadata) or the
      # scene never rendered. Scenes 2+ get keep-look for free from the chain.
      def own_first_frame_seed
        return nil unless @scene.clip.attached?

        data = nil
        @scene.clip.open do |clip|
          png = "#{clip.path}.first.png"
          Vendors::Ffmpeg::FirstFrame.call(input_path: clip.path, output_path: png)
          bytes = File.binread(png)
          File.delete(png) if File.exist?(png)
          break if bytes.bytesize > MAX_INLINE_FRAME_BYTES

          data = "data:image/png;base64,#{Base64.strict_encode64(bytes)}"
        end
        data && { primary: data, kind: :self }
      rescue StandardError => e
        Rails.logger.warn("[Video::RenderScene] own first-frame extract failed for scene #{@scene.id}: #{e.message}")
        nil
      end
    end
  end
end
