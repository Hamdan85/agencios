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
        MAX_TOKENS = 2000
        CONTEXT_MESSAGES = 24

        def initialize(creative:, message:, reference_image_urls: [])
          @creative = creative
          @message  = message.to_s.strip
          @refs     = Array(reference_image_urls).map { |u| u.to_s.strip }.reject(&:blank?)
        end

        def call
          @creative.push_chat_message(role: :user, content: @message)
          @creative.save!

          credits_before = credit_balance
          decision = decide
          edited = []
          reply  = nil
          @apply_errors = []
          @credits_short = false
          case decision['action']
          when 'edit'     then edited = apply_edits(decision)
          when 'finalize' then reply  = finalize(decision)
          when 'cancel'   then reply  = cancel(decision)
          when 'music'    then reply  = change_music(decision)
          end
          spent = [credits_before - credit_balance, 0].max

          # Out of credits mid-apply → explain in the chat (the editor is already
          # past the billing gate), never a raw 402 snackbar. A validation problem
          # (e.g. an add with no description) likewise becomes a normal reply.
          reply = insufficient_credits_reply if @credits_short && edited.blank?
          reply ||= apply_error_reply if @apply_errors.present?
          reply ||= decision['message'].to_s.strip.presence || default_reply(edited)
          @creative.push_chat_message(role: :assistant, content: reply)
          @creative.save!

          # credits_spent is surfaced to the UI, which shows the cost AFTER the
          # render finishes (as a light "pronto" pill) — not up front in the reply.
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
            try_op(position) do
              Operations::Video::EditScene.call(scene: scene, caption: spec['caption'],
                                                prompt: spec['prompt'], dialogue: spec['dialogue'],
                                                on_screen_text: spec['on_screen_text'], restyle: spec['restyle'],
                                                add_reference_urls: @refs)
            end
          end
          removal_targets = resolve(removals) # records stay valid across reindexing

          touched += adds.filter_map do |spec|
            position = [spec['scene'].to_i - 1, 0].max
            try_op(position) do
              Operations::Video::AddScene.call(creative: @creative, position: position,
                                               prompt: spec['prompt'], caption: spec['caption'],
                                               dialogue: spec['dialogue'], on_screen_text: spec['on_screen_text'],
                                               extra_reference_urls: @refs)
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
          bal = credit_balance
          "Você tem #{bal} #{bal == 1 ? 'crédito' : 'créditos'} — não é suficiente para refazer essa cena. " \
            'Compre mais créditos na sua assinatura e a gente continua. 😉'
        end

        # Turns collected validation messages into one natural chat reply.
        def apply_error_reply
          msgs = @apply_errors.uniq
          if msgs.one? && msgs.first.match?(/descrição/i)
            'Para criar essa cena eu preciso saber o que deve aparecer nela. ' \
              'Me diga o que mostrar (cenário, ação, personagens) que eu já adiciono.'
          elsif msgs.one?
            "#{msgs.first} Me diga como quer ajustar."
          else
            "Não consegui aplicar algumas mudanças: #{msgs.join('; ')}."
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

        # "Para de gerar": abandon the in-flight renders and settle the ledger.
        def cancel(decision)
          Operations::Video::CancelRender.call(creative: @creative)
          decision['message'].to_s.strip.presence ||
            'Beleza, cancelei a geração. As cenas ficam como estão — me diga o que quer fazer com elas.'
        rescue Operations::Errors::Invalid => e
          "Não deu para cancelar: #{e.message}"
        end

        # The user asked to change the background song: re-mix only (no re-render,
        # no credits). The track otherwise stays as auto-picked at generation.
        def change_music(decision)
          Operations::Video::ChangeMusic.call(creative: @creative,
                                              mood: decision['music_mood'], query: decision['music_query'])
          decision['message'].to_s.strip.presence ||
            (decision['music_mood'].to_s == 'none' ? 'Pronto, tirei a música.' : 'Beleza, troquei a trilha!')
        rescue Operations::Errors::Invalid => e
          "Não deu para trocar a música: #{e.message}"
        end

        # The user approved the draft: kick the high-quality re-render of every
        # scene. The agent's upbeat message only ships when the upgrade actually
        # starts — a blocked upgrade (still rendering / already final / no
        # credits) replies honestly in the chat instead.
        def finalize(decision)
          Operations::Video::UpgradeQuality.call(creative: @creative)
          decision['message'].to_s.strip.presence ||
            'Fechado! Gerando a versão final em alta qualidade — te aviso quando estiver pronta.'
        rescue Operations::Errors::InsufficientCredits
          insufficient_credits_reply
        rescue Operations::Errors::Invalid => e
          "Ainda não dá para finalizar: #{e.message}"
        end

        def decide
          editor = Prompts::VideoEditor.new(
            workspace: @creative.workspace, client: @creative.client, creative: @creative
          )
          client = Vendors::Ai.client(model: Vendors::Ai.model_for('video_editor'))
          base_prompt = [attachment_note, editor.turn_prompt(scenes_context, conversation)].compact.join("\n\n")

          # Weaker models sometimes answer WITHOUT the forced tool (the whole turn
          # then degrades to "não consegui processar"). Retry once with a blunt
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

        # Tells the agent the user attached reference image(s) this turn — they
        # are auto-applied to whatever scenes it EDITS or ADDS, so it must act on
        # a scene (not just reply) for the references to land.
        def attachment_note
          return nil if @refs.empty?

          "The user attached #{@refs.size} reference image(s) this turn. They will be applied to the " \
            'scene(s) you edit or add — so edit/add the relevant scene(s) and describe how to use them ' \
            '(e.g. match this product/person/style). A pure reply will NOT attach them.'
        end

        def fallback_decision
          { 'action' => 'reply', 'message' => 'Não consegui processar agora — pode reformular o que quer mudar?' }
        end

        def default_reply(edited)
          edited.any? ? "Refazendo #{edited.size == 1 ? 'a cena' : 'as cenas'} #{edited.map { |i| i + 1 }.join(', ')}…" : 'Certo.'
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
          lines = @creative.video_scenes.ordered.map do |s|
            state = STATE_LABELS.fetch(s.render_state, s.render_state)
            failure = ''
            if s.state_failed? && s.metadata['failure'].present?
              attempts = s.metadata['failure_count'].to_i
              tag = attempts > 1 ? "; failure cause (#{attempts} attempts already failed)" : '; failure cause'
              failure = "#{tag}: #{s.metadata['failure'].to_s[0, 160]}"
            end
            "Scene #{s.position + 1} — #{state}#{failure}; caption (label only): #{s.caption.presence || '—'}\n" \
              "  dialogue (spoken verbatim): #{s.metadata['dialogue'].presence&.inspect || 'none'}; " \
              "on-screen text: #{s.metadata['on_screen_text'].presence&.inspect || 'none'}\n" \
              "  full current visual prompt: #{s.prompt}"
          end
          "#{video_status_line}\n#{quality_line}\n#{audio_line}\n#{credits_line}\n#{lines.join("\n")}"
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
          else
            'VIDEO STATUS: processing — not ready yet.'
          end
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
