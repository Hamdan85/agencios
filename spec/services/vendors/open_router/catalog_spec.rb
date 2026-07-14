# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Vendors::OpenRouter::Catalog do
  subject(:catalog) { described_class.new }

  # Fakes the Faraday boundary (same pattern as the image/video client specs).
  def stub_get(path_bodies)
    conn = instance_double(Faraday::Connection)
    allow(conn).to receive(:get) do |path|
      body = path_bodies.fetch(path)
      instance_double(Faraday::Response, success?: true, body: body, status: 200)
    end
    allow(catalog).to receive(:connection).and_return(conn)
  end

  def chat_model(id, out:, name: nil)
    { 'id' => id, 'name' => name || id, 'architecture' => { 'output_modalities' => out } }
  end

  describe '#models' do
    it 'lists text models from the chat catalog (text-only outputs)' do
      stub_get('/api/v1/models' => { 'data' => [
                 chat_model('a/llm', out: %w[text]),
                 chat_model('g/imagegen', out: %w[image text])
               ] })

      expect(catalog.models(kind: 'text').map { |m| m[:id] }).to eq(%w[a/llm])
    end

    it 'lists image engines from the dedicated images catalog, excluding the auto-router' do
      stub_get('/api/v1/images/models' => { 'data' => [
                 { 'id' => 'black-forest-labs/flux.2-pro', 'name' => 'FLUX.2 Pro' },
                 { 'id' => 'openrouter/auto', 'name' => 'Auto Router' }
               ] })

      expect(catalog.models(kind: 'image')).to eq([{ id: 'black-forest-labs/flux.2-pro', name: 'FLUX.2 Pro' }])
    end

    it 'reads video engines from the dedicated videos endpoint' do
      stub_get('/api/v1/videos/models' => { 'data' => [
                 { 'id' => 'google/veo-3.1', 'name' => 'Google: Veo 3.1' },
                 { 'id' => '' }
               ] })

      expect(catalog.models(kind: 'video')).to eq([{ id: 'google/veo-3.1', name: 'Google: Veo 3.1' }])
    end

    it 'rejects an unknown kind' do
      expect { catalog.models(kind: 'audio') }.to raise_error(ArgumentError, /unknown model kind/)
    end
  end
end
