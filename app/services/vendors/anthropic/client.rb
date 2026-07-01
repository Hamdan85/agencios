# frozen_string_literal: true

module Vendors
  module Anthropic
    # Anthropic Messages API client (https://api.anthropic.com/v1/messages).
    #
    # When an API key is configured (`anthropic.api_key` credential, or the
    # `ANTHROPIC_API_KEY` env var) it makes a real call and returns the assistant
    # text. When the key is ABSENT it returns a deterministic offline stub so the
    # AI pipeline (ticket summaries, captions, scope, retrospectives) keeps working
    # in development without credentials.
    #
    # Supports the server-side `web_fetch` tool: with `web_fetch: true`, Claude
    # itself reads any URL present in the prompt and uses it as context (used by
    # the carousel generator for the "link" source).
    class Client < Vendors::Base
      BASE_URL    = 'https://api.anthropic.com'
      API_VERSION = '2023-06-01'
      # Current Sonnet — supports the web_fetch tool. Override via
      # `anthropic.model` / ANTHROPIC_MODEL.
      DEFAULT_MODEL = 'claude-sonnet-4-6'
      # web_fetch requires a current model (4.6+). Override via
      # `anthropic.fetch_model` / ANTHROPIC_FETCH_MODEL.
      DEFAULT_FETCH_MODEL = 'claude-sonnet-4-6'

      WEB_FETCH_TOOL    = { 'type' => 'web_fetch_20260209', 'name' => 'web_fetch', 'max_uses' => 5 }.freeze
      WEB_FETCH_BETA    = 'web-fetch-2025-09-10'
      MAX_TOOL_CONTINUE = 5

      attr_reader :model

      # Carries the assistant text alongside the token `usage` hash and the
      # resolved model id, so callers can record AI cost (AiUsageLog).
      Result = Struct.new(:text, :usage, :model, keyword_init: true)

      # Streaming result: the full assistant text, every captured `tool_use` block
      # (as [{ name:, input: }], possibly empty), token `usage`, and the model.
      StreamResult = Struct.new(:text, :tools, :usage, :model, keyword_init: true)

      def initialize(api_key: nil, model: nil)
        @api_key = api_key || credential(:anthropic, :api_key, env: 'ANTHROPIC_API_KEY')
        @model   = model || credential(:anthropic, :model, env: 'ANTHROPIC_MODEL').presence || DEFAULT_MODEL
      end

      # Returns the assistant text as a plain String.
      def messages(system:, prompt:, max_tokens: 1024)
        generate(system: system, prompt: prompt, max_tokens: max_tokens).text
      end

      # Like #messages but returns a Result { text, usage, model } so the caller
      # can record token cost. The offline stub returns empty usage (cost 0).
      #
      # web_fetch: true enables the server-side web_fetch tool (Claude reads URLs
      # in the prompt itself) and uses a fetch-capable model.
      def generate(system:, prompt:, max_tokens: 1024, web_fetch: false)
        target = web_fetch ? fetch_model : @model
        return Result.new(text: stub(system: system, prompt: prompt), usage: {}, model: target) if @api_key.blank?

        messages = [{ role: 'user', content: prompt.to_s }]
        body  = request(model: target, system: system, messages: messages, max_tokens: max_tokens, web_fetch: web_fetch)
        usage = usage_acc(body)

        # Server-tool loops can pause (pause_turn); resume by re-sending.
        guard = 0
        while body.is_a?(Hash) && body['stop_reason'] == 'pause_turn' && guard < MAX_TOOL_CONTINUE
          messages << { role: 'assistant', content: body['content'] }
          body = request(model: target, system: system, messages: messages, max_tokens: max_tokens,
                         web_fetch: web_fetch)
          usage = usage_acc(body, into: usage)
          guard += 1
        end

        Result.new(
          text: extract_text(body),
          usage: usage,
          model: (body.is_a?(Hash) && body['model'].presence) || target
        )
      rescue Vendors::Base::Error, Faraday::Error => e
        # Never let an AI outage (incl. timeouts) break a status transition, a
        # caption job, or a generation; fall back to the deterministic stub.
        Rails.logger.warn("[Vendors::Anthropic] #{e.class}: #{e.message} — returning stub.")
        Result.new(text: stub(system: system, prompt: prompt), usage: {}, model: target)
      end

      # Multi-turn streaming completion with optional custom tool-use. Yields
      # `text` chunks as Claude produces them (for SSE relay); returns a
      # StreamResult carrying the full text, a captured tool call (if any), token
      # usage, and the model. Used by the content-strategy planner: questions
      # stream as text, the final plan arrives as a `tool_use` block.
      #
      # `messages` is the full conversation array ([{ role:, content: }, …]).
      # When the API key is absent, a deterministic offline stub streams instead.
      def stream(system:, messages:, tools: [], max_tokens: 2048, on_tool_start: nil, &block)
        if @api_key.blank?
          return stub_stream(system: system, messages: messages, tools: tools, on_tool_start: on_tool_start,
&block)
        end

        payload = { model: @model, max_tokens: max_tokens, system: system, messages: messages, stream: true }
        payload[:tools] = tools if tools.present?

        state = { text: +'', tools: [], tool_buffers: {}, tool_meta: {}, usage: {}, on_tool_start: on_tool_start }
        buffer = +''

        stream_connection.post('/v1/messages') do |req|
          req.body = JSON.generate(payload)
          req.headers['Content-Type'] = 'application/json'
          req.options.on_data = proc do |chunk, _received|
            buffer << chunk
            while (sep = buffer.index("\n\n"))
              raw_event = buffer.slice!(0, sep + 2)
              process_sse_block(raw_event, state, &block)
            end
          end
        end

        StreamResult.new(text: state[:text], tools: state[:tools], usage: state[:usage], model: @model)
      rescue Vendors::Base::Error, Faraday::Error => e
        # Mirror #generate: never let an AI outage break the flow — fall back to
        # the deterministic offline stub so the chat still responds.
        Rails.logger.warn("[Vendors::Anthropic] stream #{e.class}: #{e.message} — returning stub.")
        stub_stream(system: system, messages: messages, tools: tools, &block)
      end

      private

      # Parse one SSE block (a `\n\n`-delimited group of lines) and fold its data
      # event into the running stream `state`, yielding text deltas as they land.
      def process_sse_block(raw_event, state, &block)
        raw_event.each_line do |line|
          line = line.strip
          next unless line.start_with?('data:')

          data = line.delete_prefix('data:').strip
          next if data.blank? || data == '[DONE]'

          event = begin
            JSON.parse(data)
          rescue StandardError
            nil
          end
          next unless event.is_a?(Hash)

          apply_stream_event(event, state, &block)
        end
      end

      def apply_stream_event(event, state, &block)
        case event['type']
        when 'message_start'
          usage = event.dig('message', 'usage')
          state[:usage] = usage if usage.is_a?(Hash)
        when 'content_block_start'
          block_data = event['content_block']
          if block_data.is_a?(Hash) && block_data['type'] == 'tool_use'
            idx = event['index']
            state[:tool_meta][idx] = { 'name' => block_data['name'] }
            state[:tool_buffers][idx] = +''
            # Signal that a tool call is starting (e.g. the plan is being built) so
            # the UI can show progress before the full JSON finishes streaming.
            state[:on_tool_start]&.call(block_data['name'])
          end
        when 'content_block_delta'
          delta = event['delta'] || {}
          case delta['type']
          when 'text_delta'
            text = delta['text'].to_s
            state[:text] << text
            block&.call(text)
          when 'input_json_delta'
            idx = event['index']
            (state[:tool_buffers][idx] ||= +'') << delta['partial_json'].to_s
          end
        when 'content_block_stop'
          idx = event['index']
          if state[:tool_meta][idx]
            parsed = begin
              JSON.parse(state[:tool_buffers][idx].to_s)
            rescue StandardError
              nil
            end
            state[:tools] << { name: state[:tool_meta][idx]['name'], input: parsed } if parsed
          end
        when 'message_delta'
          out = event.dig('usage', 'output_tokens')
          state[:usage]['output_tokens'] = out if out && state[:usage].is_a?(Hash)
        when 'error'
          raise Vendors::Base::Error, event.dig('error', 'message').to_s.presence || 'stream error'
        end
      end

      # Offline streaming stub: covers gaps for the first couple of turns, then
      # proposes a small deterministic plan so the full flow works without a key.
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

      # Yield a canned string in small chunks so the frontend sees real streaming.
      def stream_text(text, &block)
        return unless block

        text.scan(/\S+\s*/).each { |word| block.call(word) }
      end

      # A tiny deterministic content plan (4 weekly posts starting next Monday).
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

      # Streaming connection: raw SSE (no JSON response parsing, no retry buffering)
      # with a long read timeout so the model can think mid-stream.
      #
      # `Accept-Encoding: identity` is CRITICAL: Net::HTTP otherwise advertises
      # gzip and transparently decompresses the response, which forces it to read
      # the WHOLE body before yielding — so on_data would fire once at the end and
      # the tokens wouldn't stream. Identity keeps the body uncompressed and
      # delivered chunk-by-chunk as Anthropic emits each SSE event.
      def stream_connection
        @stream_connection ||= Faraday.new(url: BASE_URL) do |f|
          f.headers.merge!(
            'x-api-key' => @api_key.to_s,
            'anthropic-version' => API_VERSION,
            'Content-Type' => 'application/json',
            'Accept-Encoding' => 'identity'
          )
          f.options.timeout = 300
          f.options.open_timeout = 10
          f.adapter Faraday.default_adapter
        end
      end

      def request(model:, system:, messages:, max_tokens:, web_fetch:)
        payload = { model: model, max_tokens: max_tokens, system: system, messages: messages }
        payload[:tools] = [WEB_FETCH_TOOL] if web_fetch

        handle(connection.post('/v1/messages') do |req|
          req.body = payload
          req.headers['anthropic-beta'] = WEB_FETCH_BETA if web_fetch
        end)
      end

      def fetch_model
        credential(:anthropic, :fetch_model, env: 'ANTHROPIC_FETCH_MODEL').presence || DEFAULT_FETCH_MODEL
      end

      # Accumulate token usage across (possibly multiple) turns.
      def usage_acc(body, into: nil)
        usage = body.is_a?(Hash) && body['usage'].is_a?(Hash) ? body['usage'] : {}
        return usage if into.nil?

        %w[input_tokens output_tokens cache_creation_input_tokens
           cache_read_input_tokens].each_with_object(into.dup) do |k, acc|
          acc[k] = acc[k].to_i + usage[k].to_i
        end
      end

      def connection
        @connection ||= build_connection(
          BASE_URL,
          headers: {
            'x-api-key' => @api_key.to_s,
            'anthropic-version' => API_VERSION,
            'Content-Type' => 'application/json'
          }
        ).tap do |conn|
          # web_fetch reads full pages then writes the carousel — well past the
          # 30s default. Give the model room so it never times out mid-generation.
          conn.options.timeout = 180
          conn.options.open_timeout = 10
        end
      end

      # The Messages API returns `content` as an array of blocks; concatenate the
      # text of every `type: "text"` block (tool-use/result blocks are skipped).
      def extract_text(body)
        content = body.is_a?(Hash) ? body['content'] : nil
        return body.to_s unless content.is_a?(Array)

        content
          .select { |block| block.is_a?(Hash) && block['type'] == 'text' }
          .map { |block| block['text'] }
          .join("\n")
          .presence || ''
      end

      # Deterministic, offline placeholder echoing the head of the prompt.
      def stub(system:, prompt:)
        excerpt = prompt.to_s.strip[0, 200]
        "[stub] #{excerpt}".strip
      end
    end
  end
end
