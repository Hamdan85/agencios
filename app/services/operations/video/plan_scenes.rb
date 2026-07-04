# frozen_string_literal: true

module Operations
  module Video
    # Splits a video brief into an ordered list of SCENE specs (prompt + caption +
    # duration + seed) — the unit of independent render + edit.
    #
    # THE REQUESTED DURATION IS A HARD SCENE BUDGET. Each scene renders as one
    # model clip of ~SCENE_UNIT_SECONDS (video models return ~8s clips regardless
    # of shorter asks), so an 8s request is exactly ONE scene — never three scenes
    # that balloon into a 24s video billed at 3x.
    #
    # The scene breakdown is AI-planned (Prompts::VideoStoryboard) so the video
    # gets the RIGHT number of meaningful scenes within the budget — never filler.
    # It falls back to a deterministic beat structure when the AI is unavailable
    # (offline / no key), so generation always works and stays testable:
    #   * avatar  — the script's sentences distributed across the budgeted scenes
    #   * product — a hook → feature → CTA beat structure from the brief
    #
    # Scene prompts are stored CLEAN: the standing directives (continuity, brand,
    # legible-text) are appended at render time by Operations::Video::DecoratePrompt,
    # so chat edits keep them and the agent context stays lean. Scenes render
    # sequentially and continue from each other's last frame — see RenderScene.
    class PlanScenes < Operations::Base
      # The scene specs PLUS the video-level MUSIC SPEC the orchestrator chose
      # (search query + ffmpeg mix params). Acts as a plain Array (callers
      # `.map`/`.size`/`.first` it) with an extra `music` reader.
      class Plan < Array
        attr_accessor :music
      end

      MAX_SCENES = 6
      MIN_SCENE_SECONDS = 4
      # One scene ≈ one model clip. Veo/Seedance render ~8s per submission, so the
      # scene count must be derived from the requested duration, not invented.
      SCENE_UNIT_SECONDS = 8
      STORYBOARD_MAX_TOKENS = 2000

      PRODUCT_BEATS = [
        { key: 'hook',    caption: 'Abertura que prende a atenção', hint: 'attention-grabbing opening shot of the product' },
        { key: 'feature', caption: 'Produto em destaque',          hint: 'the product in dynamic close-up, hero framing' },
        { key: 'cta',     caption: 'Chamada para ação',            hint: 'closing call-to-action beat' }
      ].freeze

      def initialize(ctx:, mode:, script: nil, brief: nil, total_duration:, aspect_ratio:,
                     reference_image_urls: [], with_audio: nil)
        @ctx    = ctx
        @mode   = mode.to_s
        # The caller's typed params win; but ticket/autopilot flows pass none —
        # fall back to the ticket's scope so the storyboard is built from the
        # planned content (script/brief/topic), never from brand context alone.
        @script = script.presence || ctx.script
        @brief  = brief.presence || ctx.copy_brief.presence || ctx.brief.presence || ctx.topic
        @total  = total_duration.to_i
        @aspect = aspect_ratio
        @refs   = Array(reference_image_urls)
        @with_audio = with_audio
      end

      def call
        beats = ai_beats.presence || deterministic_beats
        beats = beats.first(max_scenes)
        beats = [fallback_beat] if beats.empty?
        even  = scene_duration(beats.size)
        refs  = scene_references

        specs = beats.each_with_index.map do |beat, i|
          {
            position: i,
            mode: @mode,
            prompt: beat[:prompt],
            caption: beat[:caption].to_s[0, 90],
            dialogue: beat[:dialogue],
            on_screen_text: beat[:on_screen_text],
            # The storyboard may pace each shot (cutscenes); fall back to an even split.
            duration_seconds: clamp_seconds(beat[:duration_seconds]) || even,
            # Scene 1 always establishes; later scenes CONTINUE the previous shot
            # (seamless, seeded by its last frame) UNLESS the storyboard marked a
            # CUT — a new shot with the same characters/world but a fresh framing,
            # which must NOT start from the previous frame.
            continues_previous: i.positive? && beat.fetch(:continues_previous, true),
            aspect_ratio: @aspect,
            seed: SecureRandom.hex(6),
            reference_image_urls: refs.map { |r| r[:url] },
            reference_roles: refs.map { |r| r[:role] }
          }
        end

        Plan[*specs].tap { |plan| plan.music = @music }
      end

      private

      # The scene budget CAP handed to the AI storyboard: how many ~4–8s shots
      # the total could buy, so it can pace cutscenes (several short cuts) — but
      # capped so cost stays bounded. The storyboard still uses the FEWEST needed.
      def max_scenes
        (@total / MIN_SCENE_SECONDS.to_f).ceil.clamp(1, MAX_SCENES)
      end

      # The DETERMINISTIC fallback stays conservative (one ~8s clip per beat) — it
      # is the offline path, not a place to invent cutscenes.
      def deterministic_scenes
        (@total / SCENE_UNIT_SECONDS.to_f).ceil.clamp(1, MAX_SCENES)
      end

      # Even split of the requested total across the scenes, clamped to one clip.
      def scene_duration(count)
        (@total.to_f / count).round.clamp(MIN_SCENE_SECONDS, SCENE_UNIT_SECONDS)
      end

      # A storyboard-provided per-scene duration, clamped to a single clip; nil
      # when absent (caller falls back to the even split).
      def clamp_seconds(value)
        secs = value.to_i
        return nil unless secs.positive?

        secs.clamp(MIN_SCENE_SECONDS, SCENE_UNIT_SECONDS)
      end

      # --- AI-planned storyboard (preferred) ------------------------------------
      def ai_beats
        storyboard = Prompts::VideoStoryboard.new(
          workspace: @ctx.workspace, client: @ctx.client, mode: @mode,
          brief: @brief, script: @script, total_duration: @total,
          aspect_ratio: @aspect, max_scenes: max_scenes, with_audio: @with_audio,
          # The full planning direction — what the video must SAY/SHOW/AVOID.
          objective: @ctx.objective, persona: @ctx.persona,
          content_pillar: @ctx.content_pillar, production_scope: @ctx.production_scope,
          positioning_brief: @ctx.positioning_brief, references: @ctx.references.presence&.join('; '),
          has_references: @refs.any?,
          has_logo: @mode == 'product' && @ctx.brand_logo_url.present?,
          has_avatar: @mode == 'avatar' && @ctx.brand_avatar_url.present?
        )
        client = Vendors::Ai.client(model: Vendors::Ai.model_for('video_storyboard'))
        result = client.generate(
          system: storyboard.system,
          prompt: "#{storyboard.brief_context}\n\nBuild the storyboard now by calling the tool.",
          tool: Prompts::VideoStoryboard.storyboard_tool,
          max_tokens: STORYBOARD_MAX_TOKENS
        )
        tool = result.tool_input.is_a?(Hash) ? result.tool_input : {}
        # The orchestrator's music spec: the search query + the ffmpeg mix params
        # (one track per video, burned in post). Kept only when it has a query/mood.
        m = tool['music']
        @music = m if m.is_a?(Hash) && (m['query'].present? || m['mood'].present?)
        scenes = tool['scenes']
        Array(scenes).filter_map do |s|
          prompt = s['prompt'].to_s.strip
          next if prompt.blank?

          {
            prompt: prompt,
            caption: s['caption'].to_s.strip.presence || prompt[0, 90],
            dialogue: s['dialogue'].to_s.strip.presence,
            on_screen_text: s['on_screen_text'].to_s.strip.presence,
            duration_seconds: s['duration_seconds'],
            # Default to a seamless continuation; only an explicit false is a cut.
            continues_previous: s['continues_previous'] != false
          }
        end
      rescue StandardError => e
        Rails.logger.warn("[Video::PlanScenes] storyboard AI failed, using fallback: #{e.class}: #{e.message}")
        nil
      end

      # --- deterministic fallback ----------------------------------------------
      def deterministic_beats
        @mode == 'avatar' ? avatar_beats : product_beats
      end

      # The whole script still gets delivered: sentences are grouped into the
      # budgeted scenes instead of one scene per sentence — the spoken line is a
      # FIRST-CLASS field (dialogue), never buried inside the visual prompt.
      # Scene 1 establishes; later scenes CONTINUE the same take.
      def avatar_beats
        script = (@script.presence || @brief.presence || @ctx.topic).to_s
        sentences = script.split(/(?<=[.!?])\s+/).map(&:strip).reject(&:blank?)
        sentences = [script] if sentences.empty?
        per_scene = (sentences.size.to_f / deterministic_scenes).ceil
        sentences.each_slice(per_scene).each_with_index.map do |group, i|
          line = group.join(' ')
          prompt = if i.zero?
                     'Authentic UGC talking-head, casual first-person selfie framing, natural ' \
                       'lighting. A creator speaks directly to camera, warm and confident'
                   else
                     'The SAME creator, same take and framing, keeps talking to camera — ' \
                       'continuing seamlessly, no reset'
                   end
          { caption: line[0, 90], prompt: prompt, dialogue: line }
        end
      end

      # Beats chain forward: only scene 1 states the subject; later beats advance
      # the SAME shot — restating the whole brief per scene renders N versions of
      # the same video instead of one continuous story.
      def product_beats
        subject = (@brief.presence || @ctx.topic).to_s
        PRODUCT_BEATS.first(deterministic_scenes.clamp(1, PRODUCT_BEATS.size)).each_with_index.map do |beat, i|
          prompt = if i.zero?
                     "Short vertical product video, #{beat[:hint]}. Subject: #{subject}. " \
                       'Feature the product from the reference photos faithfully — keep its exact ' \
                       'shape, colors and label; do not distort or restyle it. Dynamic, scroll-stopping motion'
                   else
                     "The SAME product video continues — next beat: #{beat[:hint]}. Keep the exact " \
                       'same product, setting, lighting and look; advance the action forward, never ' \
                       'restart or re-establish the shot'
                   end
          { caption: beat[:caption], prompt: prompt }
        end
      end

      def fallback_beat
        { prompt: @ctx.topic.to_s, caption: @ctx.topic.to_s[0, 90] }
      end

      # The visual-identity references handed to the render, per mode, each with
      # its ROLE persisted alongside the URL — so the render manifest labels every
      # image by what it IS, without re-deriving the role by URL equality against
      # a (possibly changed) brand asset at render time.
      #   product — the user's product photos + the brand logo (mark fidelity)
      #   avatar  — the creator avatar (the spokesperson's face) + any reference
      #             images the user attached to the prompt (style/subject/scene)
      def scene_references
        refs =
          if @mode == 'product'
            @refs.map { |url| { url: url, role: 'product' } } +
              [{ url: @ctx.brand_logo_url, role: 'logo' }]
          else
            [{ url: @ctx.brand_avatar_url, role: 'avatar' }] +
              @refs.map { |url| { url: url, role: 'reference' } }
          end
        refs.select { |r| r[:url].present? }
      end
    end
  end
end
