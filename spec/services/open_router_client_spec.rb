# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Vendors::OpenRouter::Client do
  let(:client) { described_class.new(api_key: 'test-key', model: 'anthropic/claude-sonnet-4.5') }

  # Fakes the Faraday boundary (the project tests vendors without real HTTP):
  # a non-streaming response, or an SSE stream fed to the client's on_data proc.
  attr_reader :last_body

  def stub_response(body:, success: true, status: 200)
    resp = instance_double(Faraday::Response, success?: success, body: body, status: status)
    conn = instance_double(Faraday::Connection)
    allow(conn).to receive(:post) do |_path, &blk|
      if blk
        req = double('req')
        allow(req).to receive(:body=) { |b| @last_body = b.is_a?(String) ? JSON.parse(b) : b.deep_stringify_keys }
        allow(req).to receive(:headers).and_return({})
        blk.call(req)
      end
      resp
    end
    allow(client).to receive(:connection).and_return(conn)
  end

  def stub_stream(sse)
    conn = instance_double(Faraday::Connection)
    allow(conn).to receive(:post) do |_path, &blk|
      req  = double('req')
      opts = double('opts')
      captured = {}
      allow(req).to receive(:body=)
      allow(req).to receive(:headers).and_return({})
      allow(req).to receive(:options).and_return(opts)
      allow(opts).to receive(:on_data=) { |proc_| captured[:on_data] = proc_ }
      blk.call(req)
      captured[:on_data].call(sse, sse.bytesize)
    end
    allow(client).to receive(:stream_connection).and_return(conn)
  end

  describe 'capabilities' do
    it 'is an OpenRouter, no-native-fetch provider' do
      expect(client.provider_key).to eq(AiUsageLog::PROVIDER_OPENROUTER)
      expect(client.supports_web_fetch?).to be(false)
    end
  end

  describe '#generate' do
    it 'returns text and normalizes usage + real cost into the ledger shape' do
      stub_response(body: {
                      'model' => 'anthropic/claude-sonnet-4.5',
                      'choices' => [{ 'message' => { 'content' => 'Olá mundo' } }],
                      'usage' => { 'prompt_tokens' => 10, 'completion_tokens' => 4, 'cost' => 0.002,
                                   'prompt_tokens_details' => { 'cached_tokens' => 3 } }
                    })

      result = client.generate(system: 'sys', prompt: 'oi', max_tokens: 100)

      # We never consume chain-of-thought, so reasoning is disabled by default.
      expect(last_body['reasoning']).to eq('enabled' => false)
      expect(result.text).to eq('Olá mundo')
      expect(result.model).to eq('anthropic/claude-sonnet-4.5')
      expect(result.usage['input_tokens']).to eq(10)
      expect(result.usage['output_tokens']).to eq(4)
      expect(result.usage['cache_read_input_tokens']).to eq(3)
      expect(result.usage['cost_cents']).to eq(0.2) # 0.002 USD → 0.2 cents
    end

    it 'forces the function call and returns its arguments parsed into a Hash' do
      tool = { 'name' => 'fill_ticket_fields', 'description' => 'x',
               'input_schema' => { 'type' => 'object', 'properties' => {} } }
      stub_response(body: {
                      'choices' => [{ 'message' => {
                        'content' => '',
                        'tool_calls' => [{ 'function' => { 'name' => 'fill_ticket_fields',
                                                           'arguments' => '{"objective":"Vender"}' } }]
                      } }],
                      'usage' => { 'prompt_tokens' => 3, 'completion_tokens' => 2 }
                    })

      result = client.generate(system: 'sys', prompt: 'oi', tool: tool)
      expect(result.tool_input).to eq('objective' => 'Vender')
    end

    it 'stubs offline when no API key is configured' do
      keyless = described_class.new(api_key: '', model: 'x/y')
      result = keyless.generate(system: 'sys', prompt: 'meu prompt')
      expect(result.text).to start_with('[stub]')
      expect(result.usage).to eq({})
    end

    it 'never raises to the caller — falls back to the stub on an API error' do
      stub_response(body: { 'error' => { 'message' => 'boom' } }, success: false, status: 500)
      result = client.generate(system: 'sys', prompt: 'meu prompt')
      expect(result.text).to start_with('[stub]')
    end
  end

  describe '#stream' do
    it 'yields text deltas and captures the accumulated tool call as a parsed Hash' do
      events = [
        { 'choices' => [{ 'delta' => { 'content' => 'Oi ' } }] },
        { 'choices' => [{ 'delta' => { 'content' => 'mundo' } }] },
        { 'choices' => [{ 'delta' => { 'tool_calls' => [
          { 'index' => 0, 'function' => { 'name' => 'propose_content_plan', 'arguments' => '{"summary":' } }
        ] } }] },
        { 'choices' => [{ 'delta' => { 'tool_calls' => [
          { 'index' => 0, 'function' => { 'arguments' => '"ok"}' } }
        ] } }] },
        { 'usage' => { 'prompt_tokens' => 5, 'completion_tokens' => 2, 'cost' => 0.001 } }
      ]
      sse = "#{events.map { |e| "data: #{e.to_json}" }.join("\n\n")}\n\ndata: [DONE]\n\n"
      stub_stream(sse)

      chunks = []
      started = []
      result = client.stream(system: 'sys', messages: [{ role: 'user', content: 'plano' }],
                             tools: [{ 'name' => 'propose_content_plan', 'input_schema' => { 'type' => 'object' } }],
                             on_tool_start: ->(name) { started << name }) { |c| chunks << c }

      expect(chunks.join).to eq('Oi mundo')
      expect(result.text).to eq('Oi mundo')
      expect(started).to eq(['propose_content_plan'])
      expect(result.tools).to eq([{ name: 'propose_content_plan', input: { 'summary' => 'ok' } }])
      expect(result.usage['cost_cents']).to eq(0.1)
    end

    it 'disables reasoning by default, and re-sends WITH reasoning when the model mandates it' do
      good = [{ 'choices' => [{ 'delta' => { 'content' => 'ok' } }] }]
      sse = "#{good.map { |e| "data: #{e.to_json}" }.join("\n\n")}\n\ndata: [DONE]\n\n"
      bodies = []
      conn = instance_double(Faraday::Connection)
      calls = 0
      allow(conn).to receive(:post) do |_path, &blk|
        calls += 1
        req = double('req'); opts = double('opts'); captured = {}
        allow(req).to receive(:body=) { |b| bodies << JSON.parse(b) }
        allow(req).to receive(:headers).and_return({})
        allow(req).to receive(:options).and_return(opts)
        allow(opts).to receive(:on_data=) { |proc_| captured[:on_data] = proc_ }
        blk.call(req)
        if calls == 1
          err = '{"error":{"message":"Reasoning is mandatory for this endpoint and cannot be disabled"}}'
          captured[:on_data].call(err, err.bytesize)
          instance_double(Faraday::Response, status: 400)
        else
          captured[:on_data].call(sse, sse.bytesize)
          instance_double(Faraday::Response, status: 200)
        end
      end
      allow(client).to receive(:stream_connection).and_return(conn)

      result = client.stream(system: 's', messages: [{ role: 'user', content: 'hi' }])
      expect(calls).to eq(2)
      expect(bodies[0]['reasoning']).to eq('enabled' => false) # 1st try: reasoning off
      expect(bodies[1]).not_to have_key('reasoning')           # retry: let it reason
      expect(result.text).to eq('ok')
    end

    it 'stubs a plan offline (no key) once enough turns have passed' do
      keyless = described_class.new(api_key: '', model: 'x/y')
      result = keyless.stream(
        system: 'sys',
        messages: [{ role: 'user', content: 'a' }, { role: 'assistant', content: 'b' }, { role: 'user', content: 'c' }],
        tools: [{ 'name' => 'propose_content_plan' }]
      )
      expect(result.tools.first[:name]).to eq('propose_content_plan')
      expect(result.tools.first[:input]['tickets'].size).to eq(4)
    end
  end
end
