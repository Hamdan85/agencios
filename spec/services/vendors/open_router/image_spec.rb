# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Vendors::OpenRouter::Image do
  subject(:image) { described_class.new(api_key: 'test-key', model: 'google/gemini-2.5-flash-image') }

  attr_reader :last_path, :last_body

  # Fakes the Faraday boundary (same pattern as the video client spec): capture
  # the POST body so we can assert the exact wire shape sent to OpenRouter.
  def stub_post(body:, success: true, status: 200)
    resp = instance_double(Faraday::Response, success?: success, body: body, status: status)
    conn = instance_double(Faraday::Connection)
    allow(conn).to receive(:post) do |path, &blk|
      @last_path = path
      if blk
        req = double('req')
        allow(req).to receive(:body=) { |b| @last_body = b.deep_stringify_keys }
        allow(req).to receive(:headers).and_return({})
        blk.call(req)
      end
      resp
    end
    allow(image).to receive(:connection).and_return(conn)
  end

  # The images API returns the generated image at data[0] as base64 + media type.
  def image_response(mime: 'image/png', b64: Base64.strict_encode64('PNGBYTES'), cost: nil)
    {
      'created' => 1_748_372_400,
      'data' => [{ 'b64_json' => b64, 'media_type' => mime }],
      'usage' => cost ? { 'cost' => cost } : {}
    }
  end

  describe '#generate_image' do
    it 'POSTs the dedicated images endpoint and returns the decoded bytes + content type + model' do
      stub_post(body: image_response(mime: 'image/png', b64: Base64.strict_encode64('PNGBYTES')))

      result = image.generate_image(prompt: 'a cheetah lawyer', aspect_ratio: '1:1')

      expect(last_path).to eq('/api/v1/images')
      expect(last_body['model']).to eq('google/gemini-2.5-flash-image')
      expect(last_body['aspect_ratio']).to eq('1:1')
      expect(last_body['n']).to eq(1)
      expect(result[:bytes]).to eq('PNGBYTES')
      expect(result[:content_type]).to eq('image/png')
      expect(result[:model]).to eq('google/gemini-2.5-flash-image')
    end

    it 'sends the aspect ratio as a param AND folds it (plus the negative prompt) into the prompt' do
      stub_post(body: image_response)

      image.generate_image(prompt: 'a cat', aspect_ratio: '9:16', negative_prompt: 'blurry')

      expect(last_body['aspect_ratio']).to eq('9:16')
      expect(last_body['prompt']).to include('a cat')
      expect(last_body['prompt']).to include('Aspect ratio: 9:16.')
      expect(last_body['prompt']).to include('Avoid: blurry.')
    end

    it 'normalizes an unsupported aspect ratio to square' do
      stub_post(body: image_response)

      image.generate_image(prompt: 'x', aspect_ratio: '21:9')

      expect(last_body['aspect_ratio']).to eq('1:1')
    end

    it 'sends reference images as input_references data URLs with a numbered legend in the prompt' do
      stub_post(body: image_response)

      image.generate_image(
        prompt: 'x', aspect_ratio: '1:1',
        reference_images: [{ label: 'BRAND LOGO', bytes: 'LOGO', content_type: 'image/png' }]
      )

      refs = last_body['input_references']
      expect(refs.size).to eq(1)
      expect(refs.first['type']).to eq('image_url')
      expect(refs.first.dig('image_url', 'url')).to eq("data:image/png;base64,#{Base64.strict_encode64('LOGO')}")
      expect(last_body['prompt']).to include('Reference images, in order: 1. BRAND LOGO.')
    end

    it 'skips reference images with an unsupported MIME type (e.g. SVG logos)' do
      stub_post(body: image_response)

      image.generate_image(
        prompt: 'x', aspect_ratio: '1:1',
        reference_images: [{ label: 'BRAND', bytes: '<svg/>', content_type: 'image/svg+xml' }]
      )

      expect(last_body).not_to have_key('input_references')
      expect(last_body['prompt']).not_to include('Reference images')
    end

    it 'passes through the real USD cost as cents when OpenRouter reports usage.cost' do
      stub_post(body: image_response(cost: 0.039))

      result = image.generate_image(prompt: 'x')

      expect(result[:cost_cents]).to be_within(0.0001).of(3.9)
    end

    it 'raises when the response carries no image' do
      stub_post(body: { 'created' => 1, 'data' => [] })

      expect { image.generate_image(prompt: 'x') }
        .to raise_error(Vendors::OpenRouter::Error, /No image returned/)
    end

    it 'raises the mapped HTTP error on a non-success response' do
      stub_post(body: { 'error' => { 'message' => 'bad model' } }, success: false, status: 400)

      expect { image.generate_image(prompt: 'x') }.to raise_error(Vendors::Base::Error)
    end
  end

  describe 'model resolution' do
    it 'uses the admin-configured ImageConfig model when none is passed' do
      ImageConfig.create!(default_model: 'black-forest-labs/flux.2-pro')
      client = described_class.new(api_key: 'test-key')
      expect(client.instance_variable_get(:@model)).to eq('black-forest-labs/flux.2-pro')
    end

    it 'falls back to the coded default when ImageConfig is blank' do
      client = described_class.new(api_key: 'test-key')
      expect(client.instance_variable_get(:@model)).to eq(described_class::DEFAULT_MODEL)
    end

    it 'an explicit model argument beats the admin config' do
      ImageConfig.create!(default_model: 'black-forest-labs/flux.2-pro')
      client = described_class.new(api_key: 'test-key', model: 'x/explicit')
      expect(client.instance_variable_get(:@model)).to eq('x/explicit')
    end
  end

  describe 'missing credentials' do
    it 'raises NotConfiguredError when no API key is set' do
      client = described_class.new(api_key: '')
      expect { client.generate_image(prompt: 'x') }
        .to raise_error(Vendors::Base::NotConfiguredError, /openrouter\.api_key/)
    end
  end
end
