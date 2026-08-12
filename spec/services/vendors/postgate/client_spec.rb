# frozen_string_literal: true

require 'rails_helper'
require 'webmock/rspec'

# Low-level PostGate HTTP wrapper. Covers auth header, payload shaping
# (nil-key omission, Idempotency-Key, comma-joined post_ids), and the house
# error-mapping contract (401/403 -> AuthenticationError, 429 -> RateLimitError,
# 5xx -> ServerError). See docs/integrations/postgate.md.
RSpec.describe Vendors::Postgate::Client do
  subject(:client) { described_class.new(api_key: 'key-123') }

  let(:base_url) { 'https://postgate.studio' }

  # Faraday only runs the JSON-parsing middleware when the response declares a
  # JSON content type (see Vendors::Base#build_connection), so every stub that
  # returns a body needs this to come back as a parsed Hash.
  def json(body, status: 200)
    { status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  describe '.configured?' do
    it 'is true when the api key is present' do
      allow(described_class).to receive(:api_key).and_return('key-123')
      expect(described_class.configured?).to be(true)
    end

    it 'is false when the api key is blank' do
      allow(described_class).to receive(:api_key).and_return(nil)
      expect(described_class.configured?).to be(false)
    end
  end

  describe '#initialize' do
    it 'raises NotConfiguredError when no api key is available' do
      allow(described_class).to receive(:api_key).and_return(nil)

      expect { described_class.new }.to raise_error(Vendors::Base::NotConfiguredError)
    end

    it 'falls back to the class-level api key when none is passed' do
      allow(described_class).to receive(:api_key).and_return('class-key')
      stub_request(:get, "#{base_url}/api/platforms").to_return(json({}))

      described_class.new.platforms

      expect(WebMock).to have_requested(:get, "#{base_url}/api/platforms")
        .with(headers: { 'Authorization' => 'Bearer class-key' })
    end
  end

  describe 'bearer auth header' do
    it 'sends Authorization: Bearer <api_key> on every request' do
      stub_request(:get, "#{base_url}/api/profile-groups").to_return(json({ data: [] }))

      client.list_profile_groups

      expect(WebMock).to have_requested(:get, "#{base_url}/api/profile-groups")
        .with(headers: { 'Authorization' => 'Bearer key-123' })
    end
  end

  describe '#create_connect_url' do
    it 'posts only the given (non-nil) fields' do
      stub_request(:post, "#{base_url}/api/profiles/connect")
        .to_return(json({ platform: 'instagram', url: 'https://connect.example/x', expires_in: 600 }))

      result = client.create_connect_url(platform: 'instagram', return_url: 'https://app.example.com/callback')

      expect(result).to eq('platform' => 'instagram', 'url' => 'https://connect.example/x', 'expires_in' => 600)
      expect(WebMock).to have_requested(:post, "#{base_url}/api/profiles/connect")
        .with(body: { platform: 'instagram', return_url: 'https://app.example.com/callback' })
    end

    it 'omits profile_group_id and instance_url when not given' do
      stub_request(:post, "#{base_url}/api/profiles/connect").to_return(json({}))

      client.create_connect_url(platform: 'mastodon')

      expect(WebMock).to have_requested(:post, "#{base_url}/api/profiles/connect")
        .with { |req| JSON.parse(req.body).keys == ['platform'] }
    end
  end

  describe '#create_post' do
    let(:payload) { { post: { body: 'hello' }, profiles: %w[profile_1], media: [] } }

    it 'sends the Idempotency-Key header when given' do
      stub_request(:post, "#{base_url}/api/posts").to_return(json({ id: 'post_1' }, status: 201))

      result = client.create_post(payload, idempotency_key: 'idem-1')

      expect(result).to eq('id' => 'post_1')
      expect(WebMock).to have_requested(:post, "#{base_url}/api/posts")
        .with(body: payload, headers: { 'Idempotency-Key' => 'idem-1' })
    end

    it 'omits the Idempotency-Key header when not given' do
      stub_request(:post, "#{base_url}/api/posts").to_return(json({}, status: 201))

      client.create_post(payload)

      expect(WebMock).to have_requested(:post, "#{base_url}/api/posts") do |req|
        !req.headers.key?('Idempotency-Key')
      end
    end
  end

  describe '#post_stats' do
    it 'comma-joins post_ids and includes from/to' do
      stub_request(:get, "#{base_url}/api/posts/stats")
        .with(query: { post_ids: 'post_1,post_2', from: '2026-01-01', to: '2026-01-31' })
        .to_return(json({ data: [] }))

      client.post_stats(post_ids: %w[post_1 post_2], from: '2026-01-01', to: '2026-01-31')

      expect(WebMock).to have_requested(:get, "#{base_url}/api/posts/stats")
        .with(query: { post_ids: 'post_1,post_2', from: '2026-01-01', to: '2026-01-31' })
    end

    it 'omits from/to from the query string when not given' do
      stub_request(:get, "#{base_url}/api/posts/stats")
        .with(query: { post_ids: 'post_1' })
        .to_return(json({ data: [] }))

      client.post_stats(post_ids: ['post_1'])

      expect(WebMock).to have_requested(:get, "#{base_url}/api/posts/stats")
        .with(query: { post_ids: 'post_1' })
    end
  end

  describe 'error mapping' do
    it 'maps 401 to AuthenticationError' do
      stub_request(:get, "#{base_url}/api/quotas")
        .to_return(json({ error: { code: 'unauthorized', message: 'bad key', retryable: false } }, status: 401))

      expect { client.quotas }.to raise_error(Vendors::Base::AuthenticationError, /bad key/)
    end

    it 'maps 429 to RateLimitError' do
      stub_request(:get, "#{base_url}/api/quotas")
        .to_return(json({ error: { code: 'rate_limited', message: 'slow down', retryable: true } }, status: 429))

      expect { client.quotas }.to raise_error(Vendors::Base::RateLimitError, /slow down/)
    end

    it 'maps 500..599 to ServerError' do
      stub_request(:get, "#{base_url}/api/quotas")
        .to_return(json({ error: { code: 'upstream_error', message: 'try later', retryable: true } }, status: 503))

      expect { client.quotas }.to raise_error(Vendors::Base::ServerError, /try later/)
    end
  end
end
