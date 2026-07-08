# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Vendors::OpenRouter::Video do
  subject(:video) { described_class.new(api_key: 'test-key') }

  attr_reader :last_body

  # Fakes the Faraday boundary (same pattern as the chat client spec): capture
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
    allow(video).to receive(:connection).and_return(conn)
  end

  describe '#submit input_references' do
    it 'wraps plain { url: } references into the image_url discriminated union' do
      stub_post(body: { 'id' => 'job_1' })

      job = video.submit(
        model: 'google/veo-3.1', prompt: 'Café gelado',
        input_references: [{ url: 'https://cdn.example.com/cup.jpg' }]
      )

      expect(job).to eq('job_1')
      expect(last_body['input_references']).to eq(
        [{ 'type' => 'image_url', 'image_url' => { 'url' => 'https://cdn.example.com/cup.jpg' } }]
      )
    end

    it 'honors an explicit reference type' do
      stub_post(body: { 'id' => 'job_2' })

      video.submit(
        model: 'google/veo-3.1', prompt: 'x',
        input_references: [{ type: 'video_url', url: 'https://cdn.example.com/clip.mp4' }]
      )

      expect(last_body['input_references']).to eq(
        [{ 'type' => 'video_url', 'video_url' => { 'url' => 'https://cdn.example.com/clip.mp4' } }]
      )
    end

    it 'omits input_references entirely when none are given' do
      stub_post(body: { 'id' => 'job_3' })

      video.submit(model: 'google/veo-3.1', prompt: 'x')

      expect(last_body).not_to have_key('input_references')
    end

    it 'never sends audio_references (OpenRouter ignores audio inputs)' do
      stub_post(body: { 'id' => 'job_a' })

      video.submit(model: 'bytedance/seedance-2.0', prompt: 'x',
                   audio_references: [{ url: 'https://cdn.example.com/voice.mp3' }])

      refs = last_body['input_references'] || []
      expect(refs.map { |r| r['type'] }).not_to include('audio_url')
      expect(last_body).not_to have_key('input_references') # no visual refs either → omitted
    end
  end

  describe '#submit generate_audio (output toggle)' do
    it 'sends generate_audio when set (false = we dub our own voice)' do
      stub_post(body: { 'id' => 'job_g' })

      video.submit(model: 'bytedance/seedance-2.0', prompt: 'x', generate_audio: false)

      expect(last_body['generate_audio']).to be(false)
    end

    it 'omits generate_audio when nil (model default)' do
      stub_post(body: { 'id' => 'job_h' })

      video.submit(model: 'bytedance/seedance-2.0', prompt: 'x')

      expect(last_body).not_to have_key('generate_audio')
    end
  end

  describe '#submit frame_images' do
    it 'normalizes { url, frame_type } into the discriminated image_url part with a suffixed frame_type' do
      stub_post(body: { 'id' => 'job_f' })

      video.submit(
        model: 'google/veo-3.1', prompt: 'x',
        frame_images: [{ url: 'https://cdn.example.com/last.png', frame_type: 'first' }]
      )

      expect(last_body['frame_images']).to eq(
        [{ 'type' => 'image_url', 'image_url' => { 'url' => 'https://cdn.example.com/last.png' },
           'frame_type' => 'first_frame' }]
      )
    end
  end

  describe '#download' do
    it 'fetches the asset with the bearer token (OpenRouter urls 401 without it)' do
      io  = StringIO.new('bytes')
      uri = instance_double(URI::HTTPS)
      allow(URI).to receive(:parse).with('https://openrouter.ai/asset/1.mp4').and_return(uri)
      allow(uri).to receive(:open).and_return(io)

      result = video.download('https://openrouter.ai/asset/1.mp4')

      expect(result).to be(io)
      expect(uri).to have_received(:open).with('Authorization' => 'Bearer test-key')
    end
  end
end
