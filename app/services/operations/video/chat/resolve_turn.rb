# frozen_string_literal: true

module Operations
  module Video
    module Chat
      # One turn of the conversational video editor. Appends the user's message,
      # asks the agent (forced-tool) whether to reply, edit, or finalize, applies
      # any per-scene edits via Operations::Video::EditScene (which handles
      # credits + re-render + recompose), records the assistant's reply, and
      # returns the fresh state. "finalize" is the approval gesture: the whole
      # storyboard re-renders with the FINAL model (UpgradeQuality) using each
      # scene's current prompt, and Compose delivers the finished single video.
      #
      # The agent decides scope — one scene, some, or all — mirroring the strategy
      # planner's router pattern. Runs in-request: the AI decision is quick; the
      # actual re-renders happen async through the scene pipeline.
      class ResolveTurn < Operations::Base
        # Generous ceiling: a truncated response loses the forced-tool call and
        # the turn degrades to the fallback reply.
        MAX_TOKENS = 3000
        # Keep a long window so the agent doesn't lose earlier context (names,
        # decisions, must-shows) as the conversation grows.
        CONTEXT_MESSAGES = 40

        # annotations: the STRUCTURED per-scene notes from the UI balloons —
        # [{ scene: 1-based number, note: text }] — sent as JSON alongside the
        # message (never concatenated into it by the client).
        # kickoff: the FIRST turn of an interview creative — no user message; the
        # agent opens the conversation (asks) instead of reacting to a message.
        # reference_descriptions: parallel to reference_image_urls — the user's
        # own words for each attached file ("what is this document?"). Merged with
        # the per-annotation descriptions into ONE { url => description } map, so
        # every downstream op (EditScene/AddScene) and the render manifest know how
        # to use each file the way the user meant.
        def initialize(creative:, message:, reference_image_urls: [], reference_descriptions: [],
                       annotations: [], kickoff: false)
          @creative    = creative
          @message     = message.to_s.strip
          @refs        = Array(reference_image_urls).map { |u| u.to_s.strip }.reject(&:blank?)
          @annotations = normalize_annotations(annotations)
          @ref_desc_map = build_description_map(reference_image_urls, reference_descriptions)
          @kickoff     = kickoff
        end

        def call
          unless @kickoff
            # The user's message keeps its attached images so the transcript shows
            # a clickable thumbnail and the agent can re-use them as context.
            @creative.push_chat_message(role: :user, content: user_message_content, images: @refs)
            @creative.save!
          end

          credits_before = credit_balance
          decision = decide
          edited = []
          reply  = nil
          @apply_errors = []
          @credits_short = false
          @edited_scene_ids = []
          @removed_scene_ids = []
          case decision['action']
          when 'edit'     then edited = apply_edits(decision)
          when 'generate' then reply  = generate(decision)
          when 'finalize' then reply  = finalize(decision)
          when 'cancel'   then reply  = cancel(decision)
          when 'music'    then reply  = change_music(decision)
          when 'identity' then reply  = change_identity(decision)
          when 'voice'    then reply  = change_voice(decision)
          end
          # A reference pinned to a scene's balloon reaches that scene REGARDLESS
          # of the agent's action (even a pure reply) — the user attached it there
          # on purpose. Skips scenes already edited/removed this turn.
          edited = (edited + apply_pinned_references(decision['reference_role'])).uniq
          spent = [credits_before - credit_balance, 0].max

          # Out of credits mid-apply → explain in the chat (the editor is already
          # past the billing gate), never a raw 402 snackbar. A validation problem
          # (e.g. an add with no description) likewise becomes a normal reply.
          reply = insufficient_credits_reply if @credits_short && edited.blank?
          reply ||= apply_error_reply if @apply_errors.present?
          reply ||= decision['message'].to_s.strip.presence || default_reply(edited)
          # Stamp the cost ON this assistant bubble so the UI shows "−N credits"
          # right under it (and the wallet counter refreshes) — not a floating pill.
          @creative.push_chat_message(role: :assistant, content: reply, credits: spent)
          @creative.save!

          { reply: reply, edited_positions: edited, action: decision['action'], credits_spent: spent }
        end

        # The workspace credit balance (0 for unlimited/godfathered — no real
        # debit, so the turn shows no cost). Reloaded so before/after are fresh.
        def credit_balance
          @creative.workspace.credit_wallet&.reload&.available.to_i
        end

        private

        # The full scene tool surface: EditScene (prompt → re-render, caption →
        # free), AddScene (add: true), ReorderScene (move_to) and RemoveScene
        # (remove: true). The agent speaks in 1-based scene numbers (what the
        # user sees); positions are 0-based. Existing targets are RESOLVED
        # before any mutation (adds/removals reindex positions), and operations
        # apply as edits → adds → moves → removals so numbers stay coherent
        # within a turn.
        def apply_edits(decision)
          specs    = Array(decision['scenes'])
          adds     = specs.select { |s| s['add'] }
          moves    = specs.select { |s| !s['add'] && !s['remove'] && s['move_to'].present? }
          removals = specs.select { |s| !s['add'] && s['remove'] }
          edits    = specs - adds - moves - removals

          touched  = resolve(edits).filter_map do |scene, spec, position|
            @edited_scene_ids << scene.id
            try_op(position) do
              Operations::Video::EditScene.call(scene: scene, caption: spec['caption'],
                                                prompt: spec['prompt'], camera: spec['camera'],
                                                dialogue: spec['dialogue'],
                                                sound_effects: spec['sound_effects'],
                                                on_screen_text: spec['on_screen_text'], restyle: spec['restyle'],
                                                # Global chat attachments + THIS scene's balloon references.
                                                add_reference_urls: @refs + annotation_refs_for(position),
                                                reference_role: decision['reference_role'],
                                                reference_descriptions: @ref_desc_map)
            end
          end
          removal_targets = resolve(removals) # records stay valid across reindexing
          @removed_scene_ids = removal_targets.map { |scene, _, _| scene.id }

          touched += adds.filter_map do |spec|
            position = [spec['scene'].to_i - 1, 0].max
            try_op(position) do
              Operations::Video::AddScene.call(creative: @creative, position: position,
                                               prompt: spec['prompt'], caption: spec['caption'],
                                               camera: spec['camera'], dialogue: spec['dialogue'],
                                               sound_effects: spec['sound_effects'],
                                               on_screen_text: spec['on_screen_text'],
                                               extra_reference_urls: @refs,
                                               reference_role: decision['reference_role'],
                                               reference_descriptions: @ref_desc_map)
            end
          end
          touched += resolve(moves).filter_map do |scene, spec, position|
            try_op(position) { Operations::Video::ReorderScene.call(scene: scene, to_position: spec['move_to'].to_i - 1) }
          end
          touched += removal_targets.filter_map do |scene, _spec, position|
            try_op(position) { Operations::Video::RemoveScene.call(scene: scene) }
          end
          touched
        end

        # For each annotated scene that carries balloon references and wasn't
        # edited/removed this turn, append them to that scene and re-render it —
        # so the reference reaches the exact scene the user pinned it to. Runs for
        # ANY action (even a pure reply); edited scenes already got their refs
        # threaded in apply_edits.
        def apply_pinned_references(reference_role)
          @annotations.filter_map do |a|
            urls = Array(a[:reference_urls])
            next if urls.empty?

            position = a[:scene] - 1
            scene = @creative.video_scenes.find_by(position: position)
            next if scene.nil? || @edited_scene_ids.include?(scene.id) || @removed_scene_ids.include?(scene.id)

            try_op(position) do
              Operations::Video::EditScene.call(scene: scene, add_reference_urls: urls,
                                                reference_role: reference_role,
                                                reference_descriptions: @ref_desc_map)
            end
          end
        end

        # The balloon references pinned to a given 0-based scene position.
        def annotation_refs_for(position)
          @annotations.find { |a| a[:scene] - 1 == position }&.fetch(:reference_urls, nil).then { |u| Array(u) }
        end

        # Runs one scene operation; a validation problem (Invalid) is collected as
        # a chat-facing note instead of blowing up the turn. InsufficientCredits
        # is NOT caught — it must surface as 402 (the billing gate).
        def try_op(position)
          yield
          position
        rescue Operations::Errors::InsufficientCredits
          @credits_short = true
          nil
        rescue Operations::Errors::Invalid => e
          @apply_errors << e.message.to_s
          nil
        end

        # Out of credits: tell the user how many they have and that they need to
        # top up — no scene was re-rendered.
        def insufficient_credits_reply
          I18n.t('operations.video.chat.insufficient_credits', count: credit_balance)
        end

        # Turns collected validation messages into one natural chat reply. The
        # single-error "needs a description" branch is detected in a
        # locale-independent way: the AddScene error carries the "descri" stem in
        # pt-BR and the "description" stem in en, so match either.
        def apply_error_reply
          msgs = @apply_errors.uniq
          if msgs.one? && msgs.first.match?(/descri|description/i)
            I18n.t('operations.video.chat.needs_description_reply')
          elsif msgs.one?
            I18n.t('operations.video.chat.apply_error_single', message: msgs.first)
          else
            I18n.t('operations.video.chat.apply_error_multiple', messages: msgs.join('; '))
          end
        end

        def resolve(specs)
          specs.filter_map do |spec|
            position = spec['scene'].to_i - 1
            next if position.negative?

            scene = @creative.video_scenes.find_by(position: position)
            scene && [scene, spec, position]
          end
        end

        # The interview gathered enough context (or the user ordered it): BUILD
        # the video now. Reuses this (draft) creative so its chat carries over,
        # then storyboard + render run off-request. Only valid before scenes
        # exist; the agent's optional `brief` is the context it consolidated.
        def generate(decision)
          return already_generating_reply if @creative.video_scenes.exists?

          intake = (@creative.metadata || {})['intake'] || {}
          Operations::Creatives::GenerateUgcVideo.call(
            ticket: @creative.ticket, creative: @creative, creative_type: @creative.creative_type,
            client_id: intake['client_id'], mode: intake['mode'],
            # Keep BOTH the agent's consolidated brief AND the user's original
            # request — the storyboard should never lose the raw details the user
            # gave (names, must-shows, exact lines) to an over-eager summary.
            prompt: build_generate_brief(decision['brief'], intake['brief']),
            voice: intake['voice'], aspect_ratio: intake['aspect_ratio'], duration: intake['duration'],
            with_audio: intake['with_audio'], reference_image_urls: Array(intake['reference_image_urls']),
            reference_descriptions: (intake['reference_descriptions'] || {})
          )
          decision['message'].to_s.strip.presence ||
            I18n.t('operations.video.chat.generate_reply')
        rescue Operations::Errors::InsufficientCredits
          insufficient_credits_reply
        rescue Operations::Errors::Invalid => e
          I18n.t('operations.video.chat.generate_error', error: e.message)
        end

        def already_generating_reply
          I18n.t('operations.video.chat.already_generating')
        end

        # Combine the agent's consolidated brief with the user's ORIGINAL request
        # so no concrete detail is lost. Skips the original if the agent already
        # subsumes it (same text), and keeps whichever is present.
        def build_generate_brief(consolidated, original)
          c = consolidated.to_s.strip
          o = original.to_s.strip
          return o if c.blank?
          return c if o.blank? || c.include?(o)

          "#{c}\n\n#{I18n.t('operations.video.chat.original_request_separator')}\n#{o}"
        end

        # "Para de gerar": abandon the in-flight renders and settle the ledger.
        def cancel(decision)
          Operations::Video::CancelRender.call(creative: @creative)
          decision['message'].to_s.strip.presence ||
            I18n.t('operations.video.chat.cancel_reply')
        rescue Operations::Errors::Invalid => e
          I18n.t('operations.video.chat.cancel_error', error: e.message)
        end

        # The user asked to change the background song: re-mix only (no re-render,
        # no credits). The track otherwise stays as auto-picked at generation.
        def change_music(decision)
          Operations::Video::ChangeMusic.call(creative: @creative,
                                              mood: decision['music_mood'], query: decision['music_query'])
          decision['message'].to_s.strip.presence ||
            (decision['music_mood'].to_s == 'none' ? I18n.t('operations.video.chat.music_removed') : I18n.t('operations.video.chat.music_changed'))
        rescue Operations::Errors::Invalid => e
          I18n.t('operations.video.chat.music_error', error: e.message)
        end

        # The user asked to change the fixed voice (narrator/speaker): swap the
        # voice_id and re-render every scene (the voice is baked via lip-sync).
        def change_voice(decision)
          Operations::Video::SetVoice.call(creative: @creative, voice: decision['voice'])
          decision['message'].to_s.strip.presence ||
            I18n.t('operations.video.chat.voice_reply')
        rescue Operations::Errors::InsufficientCredits
          insufficient_credits_reply
        rescue Operations::Errors::Invalid => e
          I18n.t('operations.video.chat.voice_error', error: e.message)
        end

        # The user changed something project-wide (character, wardrobe, setting,
        # palette, style): update the locked identity and re-render every scene.
        def change_identity(decision)
          Operations::Video::SetIdentity.call(creative: @creative, changes: decision['identity'])
          decision['message'].to_s.strip.presence ||
            I18n.t('operations.video.chat.identity_reply')
        rescue Operations::Errors::InsufficientCredits
          insufficient_credits_reply
        rescue Operations::Errors::Invalid => e
          I18n.t('operations.video.chat.identity_error', error: e.message)
        end

        # The user approved the draft: kick the high-quality re-render of every
        # scene. The agent's upbeat message only ships when the upgrade actually
        # starts — a blocked upgrade (still rendering / already final / no
        # credits) replies honestly in the chat instead.
        def finalize(decision)
          Operations::Video::UpgradeQuality.call(creative: @creative)
          decision['message'].to_s.strip.presence ||
            I18n.t('operations.video.chat.finalize_reply')
        rescue Operations::Errors::InsufficientCredits
          insufficient_credits_reply
        rescue Operations::Errors::Invalid => e
          I18n.t('operations.video.chat.finalize_error', error: e.message)
        end

        def decide
          editor = Prompts::VideoEditor.new(
            workspace: @creative.workspace, client: @creative.client, creative: @creative
          )
          client = Vendors::Ai.client(model: Vendors::Ai.model_for('video_editor'))
          base_prompt = [kickoff_note, attachment_note, annotations_note, shared_images_note,
                         editor.turn_prompt(scenes_context, conversation)].compact.join("\n\n")

          # Weaker models sometimes answer WITHOUT the forced tool (the whole turn
          # then degrades to the fallback reply). Retry once with a blunt
          # instruction before giving up — cheap insurance against a dropped call.
          2.times do |attempt|
            prompt = attempt.zero? ? base_prompt : "#{base_prompt}\n\nYou MUST call the #{Prompts::VideoEditor::EDIT_TOOL} tool now."
            result = client.generate(system: editor.system, prompt: prompt,
                                     tool: Prompts::VideoEditor.edit_tool, max_tokens: MAX_TOKENS)
            log_usage(result, client)
            return result.tool_input if result.tool_input.is_a?(Hash)

            Rails.logger.warn("[Video::Chat::ResolveTurn] no tool call (attempt #{attempt + 1}, model=#{result.model})")
          end
          fallback_decision
        rescue StandardError => e
          Rails.logger.warn("[Video::Chat::ResolveTurn] #{e.class}: #{e.message}")
          fallback_decision
        end

        # The interview's opening turn. If the user already wrote a brief (it's
        # the FIRST message above), acknowledge it and ask the first clarifying
        # question; otherwise open cold. Never generate on this turn.
        def kickoff_note
          return nil unless @kickoff

          if @creative.chat_messages.any? { |m| m['role'] == 'user' && m['content'].to_s.strip.present? }
            'This is the START of the interview and the user OPENED WITH THE BRIEF above (their first ' \
              'message). Acknowledge it briefly and warmly (Brazilian Portuguese), then ask your FIRST ' \
              'clarifying question for the biggest gap (action "reply"). Do NOT generate the video yet.'
          else
            'This is the START of the interview: the user just opened it and has not written yet. ' \
              'Open with a brief, warm Brazilian-Portuguese greeting and ask your FIRST question to ' \
              'gather what is missing (action "reply"). Do NOT generate the video yet.'
          end
        end

        # The references the user has shared ACROSS the whole chat remain in
        # context — the agent can bring any back into the render (attach it to a
        # scene it edits/adds) whenever a scene should use it.
        def shared_images_note
          urls = @creative.chat_messages.flat_map { |m| Array(m['images']) }.uniq
          return nil if urls.empty?

          "The user has shared #{urls.size} reference image(s)/video(s) in this chat; they stay available " \
            'as context. When a scene should use one, attach it to that scene (edit/add) so the render ' \
            'receives it again — decide per scene whether a reference is relevant.'
        end

        # Tells the agent the user attached media reference(s) this turn — they
        # are auto-applied to whatever scenes it EDITS or ADDS, so it must act on
        # a scene (not just reply) for the references to land, and it must
        # DECLARE what the attachment is (reference_role) from what the user said.
        def attachment_note
          return nil if @refs.empty?

          kinds = @refs.map { |u| Operations::Video::References.kind_for(u) }
          what  = kinds.include?('vid') ? 'media reference(s) (image/video)' : 'reference image(s)'
          # The user was asked "what is this file?" at upload — surface their exact
          # words so the agent uses each file as intended and picks the right role.
          described = @refs.each_with_index.filter_map do |u, i|
            desc = @ref_desc_map[u].to_s.strip
            "  - attachment #{i + 1}: #{desc.present? ? "the user says it is \"#{desc}\"" : '(no description given)'}"
          end
          "The user attached #{@refs.size} #{what} this turn. They will be applied to the " \
            "scene(s) you edit or add — so edit/add the relevant scene(s) and use each file as the user described:\n" \
            "#{described.join("\n")}\n" \
            "Set reference_role from what the user said each file IS (#{Operations::Video::References::ASSIGNABLE_ROLES.join(' / ')}): " \
            'a person/character → character; a look/aesthetic → style; a camera-movement video → camera; ' \
            'an action/choreography video → motion; a location → scene; a product photo → product. ' \
            'Unclear → omit it. A pure reply will NOT attach them.'
        end

        # Structured per-scene annotations (the UI balloons) as an explicit
        # instruction block — each note targets ITS scene, never the video as a
        # whole (free text buried notes; structure keeps the mapping exact). A
        # pinned reference is flagged so the agent edits that scene to use it (it
        # is also attached to the scene deterministically in apply_pinned_references).
        def annotations_note
          return nil if @annotations.empty?

          lines = @annotations.map do |a|
            descs = a[:reference_urls].each_index.filter_map { |i| a[:reference_descriptions][i].to_s.strip.presence }
            ref = if a[:reference_urls].present?
                    inner = descs.present? ? ": #{descs.map { |d| "\"#{d}\"" }.join(', ')}" : ''
                    " [#{a[:reference_urls].size} reference(s) attached to this scene#{inner}]"
                  else
                    ''
                  end
            "- Scene #{a[:scene]}: #{a[:note].presence || '(reference attached)'}#{ref}"
          end
          "Per-scene annotations the user pinned in the UI (apply EACH to its own scene — " \
            "combine with the message below):\n#{lines.join("\n")}"
        end

        # Keeps well-formed annotations (1-based scene number) that carry EITHER
        # a note OR a pinned reference. reference_urls ride with the scene they
        # were pinned to (the reference goes straight to that scene's render);
        # reference_descriptions is the parallel array of the user's words per file.
        def normalize_annotations(annotations)
          Array(annotations).filter_map do |a|
            h = a.respond_to?(:to_unsafe_h) ? a.to_unsafe_h : (a.respond_to?(:to_h) ? a.to_h : {})
            h = h.stringify_keys
            scene = h['scene'].to_i
            note  = h['note'].to_s.strip
            refs  = Array(h['reference_urls']).map { |u| u.to_s.strip }.reject(&:blank?)
            descs = Array(h['reference_descriptions']).map { |d| d.to_s.strip }
            next if scene < 1 || (note.blank? && refs.empty?)

            { scene: scene, note: note, reference_urls: refs, reference_descriptions: descs }
          end.sort_by { |a| a[:scene] }
        end

        # ONE { url => description } map from the turn's chat attachments AND every
        # annotation's pinned references (blob urls are unique, so a flat map is
        # safe). Downstream ops look up each url's description here.
        def build_description_map(chat_urls, chat_descs)
          map = {}
          Array(chat_urls).each_with_index do |url, i|
            u = url.to_s.strip
            map[u] = Array(chat_descs)[i].to_s.strip if u.present? && Array(chat_descs)[i].to_s.strip.present?
          end
          @annotations.each do |a|
            a[:reference_urls].each_with_index do |url, i|
              desc = a[:reference_descriptions][i].to_s.strip
              map[url] = desc if desc.present?
            end
          end
          map
        end

        # What lands in the chat HISTORY as the user's message: the typed text
        # plus the pinned notes rendered visibly (PT — user-facing), so past
        # turns keep their full instructions when replayed as agent context.
        def user_message_content
          return @message if @annotations.empty?

          notes = @annotations.map do |a|
            ref = a[:reference_urls].present? ? ' 📎' : ''
            note = a[:note].presence || I18n.t('operations.video.chat.reference_attached')
            "- #{I18n.t('operations.video.chat.scene_note', n: a[:scene], note: note)}#{ref}"
          end.join("\n")
          [@message.presence, "#{I18n.t('operations.video.chat.per_scene_notes_header')}\n#{notes}"].compact.join("\n\n")
        end

        def fallback_decision
          { 'action' => 'reply', 'message' => I18n.t('operations.video.chat.fallback') }
        end

        def default_reply(edited)
          return I18n.t('operations.video.chat.default_ack') if edited.empty?

          scenes = edited.map { |i| i + 1 }.join(', ')
          I18n.t("operations.video.chat.#{edited.size == 1 ? 'default_redo_one' : 'default_redo_many'}", scenes: scenes)
        end

        # Human-meaning per render state, so the agent never misreads (or invents)
        # what actually happened to a scene.
        STATE_LABELS = {
          'ready'     => 'READY (rendered successfully)',
          'rendering' => 'RENDERING now (wait for it to finish)',
          'fresh'     => 'NEVER RENDERED (queued / not started)',
          'stale'     => 'AWAITING re-render',
          'failed'    => 'FAILED (needs a redo)'
        }.freeze

        # The scenes as the agent's context: number (1-based, what the user sees),
        # state, caption and the FULL current visual prompt — truncated prompts
        # made the agent rewrite scenes from partial views, silently losing
        # details the user asked to keep. Prefixed by the video's overall status
        # so it can't claim success on a failed/unfinished generation.
        def scenes_context
          return intake_context if interview?

          lines = @creative.video_scenes.ordered.map do |s|
            state = STATE_LABELS.fetch(s.render_state, s.render_state)
            failure = ''
            if s.state_failed? && s.metadata['failure'].present?
              attempts = s.metadata['failure_count'].to_i
              tag = attempts > 1 ? "; failure cause (#{attempts} attempts already failed)" : '; failure cause'
              failure = "#{tag}: #{s.metadata['failure'].to_s[0, 160]}"
            end
            refs = Operations::Video::References.summary(s.labeled_references)
            "Scene #{s.position + 1} — #{state}#{failure}; caption (label only): #{s.caption.presence || '—'}\n" \
              "  dialogue (spoken verbatim): #{s.metadata['dialogue'].presence&.inspect || 'none'}; " \
              "sound effects (model-generated): #{s.metadata['sound_effects'].presence&.inspect || 'none'}; " \
              "on-screen text: #{s.metadata['on_screen_text'].presence&.inspect || 'none'}\n" \
              "  references (cite by identifier in prompts): #{refs.presence || 'none'}\n" \
              "  camera (cinematography): #{s.metadata['camera'].presence || 'none'}\n" \
              "  full current visual prompt: #{s.prompt}"
          end
          "#{video_status_line}\n#{quality_line}\n#{audio_line}\n#{identity_line}\n#{voice_line}\n#{credits_line}\n#{lines.join("\n")}"
        end

        # The fixed voice (one speaker for the whole video) + the catalog options,
        # so the agent can change it (action "voice") only when the user asks.
        def voice_line
          options = Operations::Video::VoiceOptions.list.map { |v| v[:name] }.reject(&:blank?)
          return 'VOICE: no voices available (model native audio).' if options.empty?

          current = @creative.generation&.params&.dig('voice_label').presence ||
                    @creative.generation&.params&.dig('voice_id').presence || 'default'
          "VOICE (one fixed speaker for the whole video — change project-wide via action " \
            "\"voice\", which re-renders every scene): current #{current}. Options: #{options.first(14).join(', ')}."
        end

        # Before generation: the video has NO scenes yet — the agent is INTERVIEWING.
        # Give it what's already known (from the setup) + the cost, so it only asks
        # for the real gaps and knows what a "generate" will cost.
        def interview?
          @creative.metadata.is_a?(Hash) && @creative.metadata['phase'] == 'interview' &&
            !@creative.video_scenes.exists?
        end

        def intake_context
          intake = (@creative.metadata || {})['intake'] || {}
          sound  = intake['with_audio'] == false ? 'silent (no speech)' : 'with sound'
          known  = ["format #{intake['aspect_ratio'] || '9:16'}", "~#{intake['duration']}s", sound]
          known << "initial brief: #{intake['brief']}" if intake['brief'].present?
          cost   = Pricing.credits_for(kind: :video, seconds: intake['duration'].to_i.clamp(1, 120))
          <<~TXT.strip
            PHASE: INTERVIEW — no video generated yet, so there are NO scenes. Your job now is to
            gather the COMPLETE context (see the checklist) BEFORE generating. Ask short, focused
            questions for the real GAPS only; never re-ask what is already known.
            ALREADY KNOWN (from the setup — do not ask again): #{known.join('; ')}.
            CREDITS: generating this video will cost ~#{cost} credit(s) (the user has #{credit_balance}).
            When you have enough — or the user tells you to go — use action "generate" to build it.
            Do NOT use "edit"/"finalize"/"identity"/"music" here (there are no scenes yet).
          TXT
        end

        # The locked project identity so the agent knows what to KEEP consistent
        # and can change it project-wide (action "identity") when asked.
        def identity_line
          id = @creative.generation&.params&.dig('identity')
          return 'IDENTITY: not set.' if id.blank?

          parts = []
          if id.key?('has_character')
            parts << (id['has_character'] ? "character: #{id['character'].presence || 'yes'}" : 'no character')
          end
          %w[wardrobe scenario palette style].each { |k| parts << "#{k}: #{id[k]}" if id[k].present? }
          "IDENTITY (locked, shared by every scene — change project-wide via action " \
            "\"identity\"): #{parts.join('; ')}."
        end

        # The agent always knows the wallet balance and per-op costs, so it can
        # tell the user UP FRONT when they can't afford an operation instead of
        # letting the debit fail. Free ops (caption, move, remove, change music,
        # reply) cost nothing.
        def credits_line
          bal = credit_balance
          per_scene = Pricing.credits_for(kind: :video, seconds: default_scene_seconds)
          total = @creative.video_scenes.sum { |s| Pricing.credits_for(kind: :video, seconds: s.duration_seconds.to_i) }
          "CREDITS: the user has #{bal} credit(s). Re-rendering one scene costs ~#{per_scene}; " \
            "the final high-quality upgrade re-renders every scene (~#{total} total). Caption/move/remove/" \
            'music changes and replies are FREE. If the balance does not cover an operation the user asks ' \
            'for, DO NOT attempt it — tell them they need more credits and how many, in Brazilian Portuguese.'
        end

        def default_scene_seconds
          @creative.video_scenes.first&.duration_seconds.to_i.clamp(4, 8)
        rescue StandardError
          8
        end

        # The audio tier so the agent never proposes speech on a silent video
        # (a dialogue edit there would be a charged no-op).
        def audio_line
          params = @creative.generation&.params
          silent = params&.key?('with_audio') && ActiveModel::Type::Boolean.new.cast(params['with_audio']) == false
          if silent
            'AUDIO: this video is SILENT — it has NO speech. Do not offer or set dialogue; ' \
              'suggest on-screen text instead if the user wants a message.'
          else
            'AUDIO: sound is ON — dialogue is spoken. Set the exact spoken line in the ' \
              'scene\'s dialogue field (not in the visual prompt).'
          end
        end

        # Whether the video is still the cheap draft preview (finalize available)
        # or already the final render — the agent must never offer/claim the
        # wrong tier.
        def quality_line
          if @creative.generation&.params&.dig('quality') == 'draft'
            'QUALITY: DRAFT preview (fast model). When the user approves the video, ' \
              'action "finalize" renders the final high-quality version.'
          else
            'QUALITY: FINAL (best model) — "finalize" is not applicable.'
          end
        end

        # Honest overall status: a failed generation may still have rendered
        # scenes — say exactly which failed and WHY, so the agent can rewrite
        # around the cause (e.g. an engine safety filter) instead of guessing.
        def video_status_line
          gen = @creative.generation
          if @creative.status_failed? || gen&.status_failed?
            failed = @creative.video_scenes.state_failed.order(:position).pluck(:position).map { |p| p + 1 }
            which = failed.any? ? "scene(s) #{failed.join(', ')} FAILED" : 'a scene failed'
            reason = gen&.failure_reason.presence
            detail = reason ? " Engine error: #{reason[0, 180]}." : ''
            "VIDEO STATUS: FAILED — #{which}; the other scenes keep their renders.#{detail} " \
              'To retry, use "edit" on the failed scene(s) — rewrite the prompt to avoid the error cause.'
          elsif @creative.status_ready?
            'VIDEO STATUS: ready (composed).'
          elsif rendering?
            'VIDEO STATUS: GENERATING right now — scenes are still rendering (~1–2 min each). ' \
              'The user is waiting on this render. Acknowledge that the video is being generated ' \
              'and ask them to hold on a moment; only note down any change they ask for. Do NOT ' \
              'start a NEW render (edit/finalize/identity/voice) on top of the one in flight unless ' \
              'they explicitly insist — reply warmly and ask for a little patience.'
          else
            'VIDEO STATUS: processing — not ready yet.'
          end
        end

        # A render is actively in flight (scenes rendering or queued behind one).
        def rendering?
          @creative.status_generating? ||
            @creative.video_scenes.where(render_state: %i[rendering fresh stale]).exists?
        end

        def conversation
          @creative.chat_messages.last(CONTEXT_MESSAGES).filter_map do |m|
            content = m['content'].to_s.strip
            next if content.blank?

            "#{m['role'] == 'assistant' ? 'EDITOR' : 'USER'}: #{content}"
          end.join("\n\n")
        end

        def log_usage(result, client)
          Operations::Ai::LogUsage.call(
            provider: client.provider_key, operation: 'video_editor', model: result.model,
            usage: result.usage,
            cost_cents: result.usage.is_a?(Hash) ? result.usage['cost_cents'] : nil,
            subject: @creative, workspace: @creative.workspace, user: Current.user
          )
        rescue StandardError
          nil
        end
      end
    end
  end
end
