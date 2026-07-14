# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Vendors::OpenRouter::Image do
  subject(:image) { described_class.new(api_key: 'test-key', model: 'google/gemini-2.5-flash-image') }

  attr_reader :last_body

  # Fakes the Faraday boundary (same pattern as the video client spec): capture
  # the POST body so we can assert the exact wire shape sent to OpenRouter.
  def stub_post(body:, success: true, status: 200)
    resp = instance_double(Faraday::Response, success?: success, body: body, status: status)
    conn = instance_double(Faraday::Connection)
    allow(conn).to receive(:post) do |_path, &blk|
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

  # OpenRouter returns the generated image inline on message.images[] as a data URI.
  def image_response(mime: 'image/png', b64: Base64.strict_encode64('PNGBYTES'), cost: nil)
    {
      'choices' => [{ 'message' => { 'content' => 'here', 'images' => [
        { 'type' => 'image_url', 'image_url' => { 'url' => "data:#{mime};base64,#{b64}" } }
      ] } }],
      'usage' => cost ? { 'cost' => cost } : {}
    }
  end

  describe '#generate_image' do
    it 'requests the image+text modalities and returns the decoded bytes + content type' do
      stub_post(body: image_response(mime: 'image/png', b64: Base64.strict_encode64('PNGBYTES')))

      result = image.generate_image(prompt: 'a cheetah lawyer', aspect_ratio: '1:1')

      expect(last_body['model']).to eq('google/gemini-2.5-flash-image')
      expect(last_body['modalities']).to eq(%w[image text])
      expect(last_body.dig('messages', 0, 'role')).to eq('user')
      expect(result[:bytes]).to eq('PNGBYTES')
      expect(result[:content_type]).to eq('image/png')
    end

    it 'folds the aspect ratio and negative prompt into the text part' do
      stub_post(body: image_response)

      image.generate_image(prompt: 'a cat', aspect_ratio: '9:16', negative_prompt: 'blurry')

      text = last_body.dig('messages', 0, 'content', 0, 'text')
      expect(text).to include('a cat')
      expect(text).to include('Aspect ratio: 9:16.')
      expect(text).to include('Avoid: blurry.')
    end

    it 'attaches supported reference images as inline image_url data URIs' do
      stub_post(body: image_response)

      image.generate_image(
        prompt: 'x', aspect_ratio: '1:1',
        reference_images: [{ label: 'MARCA', bytes: 'LOGO', content_type: 'image/png' }]
      )

      parts = last_body.dig('messages', 0, 'content')
      label = parts.find { |p| p['type'] == 'text' && p['text'].to_s.include?('MARCA') }
      img   = parts.find { |p| p['type'] == 'image_url' }
      expect(label).to be_present
      expect(img.dig('image_url', 'url')).to eq("data:image/png;base64,#{Base64.strict_encode64('LOGO')}")
    end

    it 'skips reference images with an unsupported MIME type (e.g. SVG logos)' do
      stub_post(body: image_response)

      image.generate_image(
        prompt: 'x', aspect_ratio: '1:1',
        reference_images: [{ label: 'MARCA', bytes: '<svg/>', content_type: 'image/svg+xml' }]
      )

      parts = last_body.dig('messages', 0, 'content')
      expect(parts.select { |p| p['type'] == 'image_url' }).to be_empty
    end

    it 'passes through the real USD cost as cents when OpenRouter reports usage.cost' do
      stub_post(body: image_response(cost: 0.039))

      result = image.generate_image(prompt: 'x')

      expect(result[:cost_cents]).to be_within(0.0001).of(3.9)
    end

    it 'raises when the response carries no image' do
      stub_post(body: { 'choices' => [{ 'message' => { 'content' => 'no image' } }] })

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
      ImageConfig.create!(default_model: 'stability/sd-ultra')
      client = described_class.new(api_key: 'test-key')
      expect(client.instance_variable_get(:@model)).to eq('stability/sd-ultra')
    end

    it 'falls back to the coded default when ImageConfig is blank' do
      client = described_class.new(api_key: 'test-key')
      expect(client.instance_variable_get(:@model)).to eq(described_class::DEFAULT_MODEL)
    end

    it 'an explicit model argument beats the admin config' do
      ImageConfig.create!(default_model: 'stability/sd-ultra')
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
