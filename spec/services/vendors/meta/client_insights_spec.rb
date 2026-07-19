# frozen_string_literal: true

require 'rails_helper'

# Graph fails the WHOLE /insights request on one bad metric name, in two different
# shapes. Both must degrade to "return what still works" — a retired metric family
# silently zeroing every post is exactly the bug this guards.
RSpec.describe Vendors::Meta::Client do
  let(:account) do
    SocialAccount.new(provider: 'facebook', connection_type: 'facebook_login', page_access_token: 'tok')
  end
  let(:client) { described_class.new(account) }
  let(:path) { '/123_456/insights' }

  def graph_error(message, code: 100, status: 400)
    Vendors::Base::Error.new(
      message,
      status: status,
      body: { 'error' => { 'message' => message, 'code' => code, 'type' => 'OAuthException' } }
    )
  end

  def datum(name, value)
    { 'name' => name, 'values' => [{ 'value' => value }] }
  end

  describe '#insights_get' do
    it 'probes metrics one by one when Graph rejects the batch without naming a position' do
      allow(client).to receive(:get).with(path, params: { metric: 'post_views,post_impressions' })
                                    .and_raise(graph_error('(#100) The value must be a valid insights metric'))
      allow(client).to receive(:get).with(path, params: { metric: 'post_views' })
                                    .and_raise(graph_error('(#100) The value must be a valid insights metric'))
      allow(client).to receive(:get).with(path, params: { metric: 'post_impressions' })
                                    .and_return({ 'data' => [datum('post_impressions', 42)] })

      body = client.insights_get(path, metrics: %w[post_views post_impressions])

      expect(body['data']).to eq([datum('post_impressions', 42)])
    end

    it 'returns an empty data set when every probed metric is rejected' do
      allow(client).to receive(:get).and_raise(graph_error('(#100) The value must be a valid insights metric'))

      expect(client.insights_get(path, metrics: %w[a b])).to eq({ 'data' => [] })
    end

    it 'still drops by position when Graph names one (the indexed shape)' do
      allow(client).to receive(:get).with(path, params: { metric: 'good,bad' })
                                    .and_raise(graph_error('metric[1] must be one of the following values: good'))
      allow(client).to receive(:get).with(path, params: { metric: 'good' })
                                    .and_return({ 'data' => [datum('good', 7)] })

      body = client.insights_get(path, metrics: %w[good bad])

      expect(body['data']).to eq([datum('good', 7)])
    end

    it 'propagates errors that are not about a metric name' do
      allow(client).to receive(:get)
        .and_raise(graph_error("(#10) This endpoint requires the 'pages_read_engagement' permission", code: 10))

      expect { client.insights_get(path, metrics: %w[a]) }.to raise_error(Vendors::Base::Error, /pages_read_engagement/)
    end
  end

  describe 'dead-token mapping' do
    def response_double(code:, message: 'boom', status: 400)
      instance_double(
        Faraday::Response,
        success?: false,
        status: status,
        body: { 'error' => { 'message' => message, 'code' => code, 'type' => 'OAuthException' } }
      )
    end

    it 'raises AuthenticationError for a finished token (#190) even though Graph answers 400' do
      response = response_double(code: 190, message: 'Invalid OAuth access token - Cannot parse access token')

      expect { client.send(:handle, response) }
        .to raise_error(Vendors::Base::AuthenticationError, /Invalid OAuth access token/)
    end

    it 'leaves a permission gap (#10) as a plain error — reconnecting cannot fix it' do
      response = response_double(code: 10, message: "(#10) requires the 'pages_read_engagement' permission")

      expect { client.send(:handle, response) }.to raise_error(Vendors::Base::Error) do |error|
        expect(error).not_to be_a(Vendors::Base::AuthenticationError)
      end
    end
  end
end
