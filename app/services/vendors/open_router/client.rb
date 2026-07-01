# frozen_string_literal: true

module Vendors
  module OpenRouter
    # OpenRouter chat-completions client (https://openrouter.ai/api/v1). OpenAI-
    # compatible, so ANY model (Claude, GPT, Gemini, DeepSeek, Llama…) is reachable
    # by slug — the platform picks per operation to trade quality against cost.
    #
    # Drop-in replacement for Vendors::Anthropic::Client: same public methods
    # (#messages / #generate / #stream) and the same Vendors::Ai result structs.
    # Provider-specific translation lives ENTIRELY here:
    #   * system prompt → a leading {role:"system"} message
    #   * Anthropic tool schema {name,description,input_schema} → OpenAI `function`
    #   * tool output: tool_calls[].function.arguments (JSON string) → parsed Hash
    #   * usage: prompt/completion_tokens → input/output_tokens, plus REAL USD cost
    #     (OpenRouter `usage.cost`, requested via `usage:{include:true}`)
    #
    # Matches the Anthropic client's safety contract: never raises to the caller
    # (API/timeout errors fall back to the deterministic offline stub), and stubs
    # when no API key is configured so dev works without credentials.
    class Client < Vendors::Base
      BASE_URL = 'https://openrouter.ai'
      # Defaults to Claude via OpenRouter so behavior is identical to the direct
      # Anthropic path on day one; cheaper models are opt-in per operation
      # (`openrouter.models`) or via `openrouter.model` / OPENROUTER_MODEL.
      DEFAULT_MODEL = 'anthropic/claude-sonnet-4.5'

      Result       = Vendors::Ai::Result
      StreamResult = Vendors::Ai::StreamResult

      attr_reader :model

      def initialize(api_key: nil, model: nil)
        @api_key = api_key || credential(:openrouter, :api_key, env: 'OPENROUTER_API_KEY')
        @model   = model.presence ||
                   credential(:openrouter, :model, env: 'OPENROUTER_MODEL').presence ||
                   DEFAULT_MODEL
      end

      # Which ledger bucket this client's calls belong to.
      def provider_key = AiUsageLog::PROVIDER_OPENROUTER

      # OpenRouter has no standardized server-side URL-reading tool; the AiAdapter
      # inlines page content into the prompt itself instead (Vendors::Web::Reader).
      def supports_web_fetch? = false

      # Assistant text as a plain String.
      def messages(system:, prompt:, max_tokens: 1024)
        generate(system: system, prompt: prompt, max_tokens: max_tokens).text
      end

      # Full completion returning a Result { text, usage, model, tool_input }.
      # `web_fetch:` is accepted for signature-compat with the Anthropic client and
      # ignored here (see #supports_web_fetch?). `tool:` (an Anthropic-shaped tool
      # schema) forces a function call and returns its parsed input as tool_input.
      # `reasoning: true` lets the model reason (omits the disable flag) — use it
      # for non-streamed calls where the reasoning improves output quality and the
      # reset risk doesn't apply (there's no long chunked read to reset).
      def generate(system:, prompt:, max_tokens: 1024, web_fetch: false, tool: nil, reasoning: false)
        _ = web_fetch
        if @api_key.blank?
          warn_missing_key
          return Result.new(text: stub(system: system, prompt: prompt), usage: {}, model: @model, tool_input: nil)
        end

        msgs = [{ role: 'system', content: system.to_s }, { role: 'user', content: prompt.to_s }]
        reasoning_enabled = reasoning
        begin
          payload = base_payload(messages: msgs, max_tokens: max_tokens, tool: tool, reasoning_enabled: reasoning_enabled)
          body = handle(connection.post('/api/v1/chat/completions') { |req| req.body = payload })
        rescue Vendors::Base::Error => e
          # This model requires reasoning — resend letting it reason.
          raise unless !reasoning_enabled && reasoning_mandatory?(e)

          reasoning_enabled = true
          retry
        end

        Result.new(
          text: extract_text(body),
          tool_input: tool && extract_tool_input(body, tool['name']),
          usage: normalize_usage(body.is_a?(Hash) ? body['usage'] : nil),
          model: (body.is_a?(Hash) && body['model'].presence) || @model
        )
      rescue Vendors::Base::Error, Faraday::Error => e
        Rails.logger.warn("[Vendors::OpenRouter] #{e.class}: #{e.message} — returning stub.")
        Result.new(text: stub(system: system, prompt: prompt), usage: {}, model: @model, tool_input: nil)
      end

      # Multi-turn streaming completion with optional tool-use. Yields text chunks
      # as they arrive; returns a StreamResult { text, tools, usage, model }.
      # `messages` is the full conversation ([{ role:, content: }, …]).
      def stream(system:, messages:, tools: [], max_tokens: 2048, on_tool_start: nil, &block)
        if @api_key.blank?
          warn_missing_key
          return stub_stream(system: system, messages: messages, tools: tools, on_tool_start: on_tool_start, &block)
        end

        msgs = [{ role: 'system', content: system.to_s }] + Array(messages)
        reasoning_enabled = false
        state = new_stream_state(on_tool_start)
        begin
          payload = base_payload(messages: msgs, max_tokens: max_tokens, tools: tools,
                                 reasoning_enabled: reasoning_enabled).merge(stream: true, stream_options: { include_usage: true })
          state = new_stream_state(on_tool_start)
          run_stream(payload, state, &block)
        rescue Vendors::Base::Error => e
          # This model requires reasoning — resend letting it reason (nothing has
          # streamed yet on a request-validation error, so it's safe to restart).
          raise unless !reasoning_enabled && reasoning_mandatory?(e) && state[:text].empty?

          reasoning_enabled = true
          retry
        end

        finalize_tools(state)
        StreamResult.new(text: state[:text], tools: state[:tools], usage: state[:usage], model: @model)
      rescue Vendors::Base::Error, Faraday::Error => e
        Rails.logger.warn("[Vendors::OpenRouter] stream #{e.class}: #{e.message} — returning stub.")
        stub_stream(system: system, messages: messages, tools: tools, &block)
      end

      private

      # Shared request body. `usage: { include: true }` asks OpenRouter to report
      # the real generation cost (USD) in the response `usage.cost`.
      #
      # We NEVER consume chain-of-thought (delta.reasoning / message.reasoning are
      # ignored everywhere), so by default we ask the model not to generate it
      # (`reasoning: {enabled:false}`). Reasoning models otherwise stream hundreds
      # of KB of CoT before the answer — that long transfer inflates cost/latency
      # and is exactly what intermittently trips "Connection reset by peer"
      # mid-stream (→ the offline stub, usage 0/0). A few models MANDATE reasoning
      # and reject this; callers retry with `reasoning_enabled: true` in that case.
      def base_payload(messages:, max_tokens:, tools: nil, tool: nil, reasoning_enabled: false)
        payload = { model: @model, max_tokens: max_tokens, messages: messages, usage: { include: true } }
        payload[:reasoning] = { enabled: false } unless reasoning_enabled
        list = Array(tools).map { |t| to_openai_tool(t) }
        list << to_openai_tool(tool) if tool
        if list.any?
          payload[:tools] = list
          payload[:tool_choice] = { type: 'function', function: { name: tool['name'] } } if tool
        end
        payload
      end

      # Anthropic tool schema → OpenAI `function` tool.
      def to_openai_tool(tool)
        {
          'type' => 'function',
          'function' => {
            'name' => tool['name'] || tool[:name],
            'description' => tool['description'] || tool[:description],
            'parameters' => tool['input_schema'] || tool[:input_schema] || { 'type' => 'object', 'properties' => {} }
          }
        }
      end

      def extract_text(body)
        msg = body.is_a?(Hash) ? body.dig('choices', 0, 'message') : nil
        return '' unless msg.is_a?(Hash)

        msg['content'].to_s
      end

      # The structured input of the forced `function` call — parsed from the
      # arguments JSON STRING (OpenAI-compat) into a Hash. nil if absent/invalid.
      def extract_tool_input(body, tool_name)
        calls = body.is_a?(Hash) ? body.dig('choices', 0, 'message', 'tool_calls') : nil
        return nil unless calls.is_a?(Array)

        call = calls.find { |c| c.is_a?(Hash) && c.dig('function', 'name') == tool_name } || calls.first
        args = call&.dig('function', 'arguments')
        parse_json(args)
      end

      # OpenAI usage (prompt/completion_tokens, prompt_tokens_details.cached_tokens)
      # → the Anthropic-shaped keys the ledger reads, plus the real cost in cents
      # (OpenRouter `usage.cost` is USD) so LogUsage stores it verbatim.
      def normalize_usage(usage)
        return {} unless usage.is_a?(Hash)

        out = {
          'input_tokens' => usage['prompt_tokens'].to_i,
          'output_tokens' => usage['completion_tokens'].to_i,
          'cache_read_input_tokens' => usage.dig('prompt_tokens_details', 'cached_tokens').to_i
        }
        out['cost_cents'] = usage['cost'].to_f * 100.0 if usage['cost']
        out
      end

      # --- streaming SSE ---------------------------------------------------------

      def new_stream_state(on_tool_start)
        { text: +'', tool_meta: {}, tool_buffers: {}, tools: [], usage: {}, on_tool_start: on_tool_start }
      end

      def run_stream(payload, state, &block)
        buffer = +''
        head   = +'' # first bytes kept for error reporting on a non-2xx response
        resp = stream_connection.post('/api/v1/chat/completions') do |req|
          req.body = JSON.generate(payload)
          req.headers['Content-Type'] = 'application/json'
          req.options.on_data = proc do |chunk, _received|
            head << chunk if head.bytesize < 2048
            buffer << chunk
            while (sep = buffer.index("\n\n"))
              raw_event = buffer.slice!(0, sep + 2)
              process_sse_block(raw_event, state, &block)
            end
          end
        end

        # A request-validation error (e.g. mandatory reasoning) comes back as a
        # normal non-2xx JSON body, not SSE — surface it so callers can adapt.
        status = resp.respond_to?(:status) ? resp.status.to_i : 0
        raise Vendors::Base::Error.new(error_from_raw(head), status: status) if status >= 400
      end

      # True when a non-2xx error says the model can't run without reasoning.
      def reasoning_mandatory?(err)
        return false unless err.respond_to?(:status) && [400, 404, 422].include?(err.status.to_i)

        msg = err.message.to_s
        msg.match?(/reasoning/i) && msg.match?(/mandatory|cannot be disabled|required|must be enabled/i)
      end

      def error_from_raw(raw)
        parsed = parse_json(raw)
        (parsed.is_a?(Hash) && (parsed.dig('error', 'message') || parsed['error']).to_s.presence) ||
          raw.to_s[0, 200].presence || 'stream error'
      end

      def process_sse_block(raw_event, state, &block)
        raw_event.each_line do |line|
          line = line.strip
          next unless line.start_with?('data:')

          data = line.delete_prefix('data:').strip
          next if data.blank? || data == '[DONE]'

          event = parse_json(data)
          apply_stream_event(event, state, &block) if event.is_a?(Hash)
        end
      end

      def apply_stream_event(event, state, &block)
        usage = event['usage']
        state[:usage] = normalize_usage(usage) if usage.is_a?(Hash)

        delta = event.dig('choices', 0, 'delta')
        return unless delta.is_a?(Hash)

        text = delta['content']
        if text.is_a?(String) && !text.empty?
          state[:text] << text
          block&.call(text)
        end

        Array(delta['tool_calls']).each { |call| accumulate_tool_call(call, state) }
      end

      # tool_calls stream as indexed fragments: the first fragment for an index
      # carries the function name; later fragments append `arguments` text.
      def accumulate_tool_call(call, state)
        return unless call.is_a?(Hash)

        idx  = call['index'] || 0
        name = call.dig('function', 'name')
        if name.present? && state[:tool_meta][idx].nil?
          state[:tool_meta][idx] = { 'name' => name }
          state[:tool_buffers][idx] = +''
          state[:on_tool_start]&.call(name)
        end
        args = call.dig('function', 'arguments')
        (state[:tool_buffers][idx] ||= +'') << args.to_s if args
      end

      # Parse each captured tool call's accumulated arguments JSON into the final
      # [{ name:, input: Hash }] shape (dropping any that failed to parse).
      def finalize_tools(state)
        state[:tool_meta].each do |idx, meta|
          parsed = parse_json(state[:tool_buffers][idx])
          state[:tools] << { name: meta['name'], input: parsed } if parsed
        end
      end

      def parse_json(str)
        return nil if str.to_s.strip.empty?

        JSON.parse(str)
      rescue StandardError
        nil
      end

      # --- connections -----------------------------------------------------------

      def connection
        @connection ||= build_connection(BASE_URL, headers: default_headers).tap do |conn|
          # Inlined page content + long generations run well past the 30s default.
          conn.options.timeout = 180
          conn.options.open_timeout = 10
        end
      end

      # Raw SSE stream: `Accept-Encoding: identity` keeps the body uncompressed so
      # tokens arrive chunk-by-chunk (gzip would force reading the whole body first).
      def stream_connection
        @stream_connection ||= Faraday.new(url: BASE_URL) do |f|
          f.headers.merge!(default_headers.merge('Accept-Encoding' => 'identity'))
          f.options.timeout = 300
          f.options.open_timeout = 10
          f.adapter Faraday.default_adapter
        end
      end

      # OpenRouter recommends HTTP-Referer + X-Title for attribution/ranking.
      def default_headers
        {
          'Authorization' => "Bearer #{@api_key}",
          'Content-Type' => 'application/json',
          'HTTP-Referer' => SystemConfig.app_host,
          'X-Title' => 'agencios'
        }
      end

      # --- offline stubs (mirror the Anthropic client) ---------------------------

      # No OpenRouter key → every call returns the offline stub. This is expected
      # in dev without credentials, but a common surprise in a running app: the
      # key was added to credentials AFTER boot (credentials load once, at boot) —
      # restart Puma/Sidekiq. Warn ONCE per process so it's diagnosable, not noisy.
      def warn_missing_key
        return if self.class.instance_variable_get(:@warned_missing_key)

        self.class.instance_variable_set(:@warned_missing_key, true)
        Rails.logger.warn('[Vendors::OpenRouter] No API key (openrouter.api_key / OPENROUTER_API_KEY) — ' \
                          'returning the OFFLINE STUB for every call. If you just added the key to ' \
                          'credentials, restart the server and Sidekiq (credentials load at boot).')
      end

      def stub(system:, prompt:)
        _ = system
        "[stub] #{prompt.to_s.strip[0, 200]}".strip
      end

      def stub_stream(system:, messages:, tools:, on_tool_start: nil, &block)
        _ = system
        user_turns = Array(messages).count { |m| (m[:role] || m['role']).to_s == 'user' }
        wants_tool = tools.present? && user_turns >= 2

        if wants_tool
          text = 'Fechado. Montei um plano inicial com base na cadência combinada — revise e ajuste o que precisar.'
          stream_text(text, &block)
          plan_tool = tools.find { |t| (t['name'] || t[:name]).to_s.include?('plan') } || tools.first
          tool_name = plan_tool['name'] || plan_tool[:name]
          on_tool_start&.call(tool_name)
          StreamResult.new(text: text, tools: [{ name: tool_name, input: stub_plan }], usage: {}, model: @model)
        else
          text = 'Antes de montar o plano: quais redes e qual a janela (ex.: o mês inteiro)? ' \
                 'E quais dias/horários você prefere postar?'
          stream_text(text, &block)
          StreamResult.new(text: text, tools: [], usage: {}, model: @model)
        end
      end

      def stream_text(text, &block)
        return unless block

        text.scan(/\S+\s*/).each { |word| block.call(word) }
      end

      def stub_plan
        start = Date.current.next_week(:monday)
        tickets = Array.new(4) do |i|
          post_at = (start + (i * 7)).to_time.change(hour: 10)
          {
            'title' => "Post semanal #{i + 1}",
            'creative_type' => i.even? ? 'reel' : 'carousel',
            'channels' => %w[instagram],
            'priority' => 'medium',
            'scheduled_at' => post_at.iso8601,
            'brief' => 'Conteúdo alinhado aos pilares da marca.',
            'subtasks' => [
              { 'title' => 'Roteiro e briefing', 'estimate_hours' => 2, 'lead_offset_days' => 5 },
              { 'title' => 'Produção do criativo', 'estimate_hours' => 4, 'lead_offset_days' => 3 },
              { 'title' => 'Revisão e aprovação', 'estimate_hours' => 1, 'lead_offset_days' => 1 }
            ]
          }
        end
        { 'summary' => 'Plano de teste (stub offline): 4 posts semanais.', 'tickets' => tickets }
      end
    end
  end
end
