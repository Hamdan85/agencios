# frozen_string_literal: true

require 'rails_helper'

# The voice source: LIVE Cartesia library (so the orchestrator picks the best
# voice for a character) + the optional admin catalog, and how a pick resolves
# to a concrete voice_id.
RSpec.describe Operations::Video::VoiceOptions do
  let(:live) do
    [{ id: 'live_fem', name: 'Ana', gender: 'female', description: 'jovem, animada', language: 'pt' },
     { id: 'live_masc', name: 'Bruno', gender: 'male', description: 'grave', language: 'pt' }]
  end

  describe '.list' do
    it 'lists live Cartesia voices first, then admin entries not already present' do
      allow(Vendors::Cartesia::Actions::ListVoices).to receive(:call).and_return(live)
      allow(VideoConfig).to receive(:instance).and_return(
        VideoConfig.new(voice_catalog: { 'Marca' => 'admin_x', 'Dup' => 'live_fem' })
      )

      names = described_class.list.map { |v| v[:name] }
      expect(names).to eq(%w[Ana Bruno Marca]) # 'Dup' dropped (id already live)
    end
  end

  describe '.resolve (strict)' do
    before do
      allow(Vendors::Cartesia::Actions::ListVoices).to receive(:call).and_return(live)
      allow(VideoConfig).to receive(:instance).and_return(VideoConfig.new(voice_catalog: { 'Marca' => 'admin_x' }))
    end

    it 'matches a live voice by name (case-insensitive) or raw id' do
      expect(described_class.resolve('ana')).to eq('live_fem')
      expect(described_class.resolve('live_masc')).to eq('live_masc')
    end

    it 'matches an admin catalog label or its id' do
      expect(described_class.resolve('Marca')).to eq('admin_x')
      expect(described_class.resolve('admin_x')).to eq('admin_x')
    end

    it 'returns nil for an unknown pick (so SetVoice can refuse it)' do
      expect(described_class.resolve('Inexistente')).to be_nil
      expect(described_class.resolve(nil)).to be_nil
    end
  end

  describe '.resolve_or_default (lenient)' do
    it 'falls back to the admin default, then the first live voice' do
      allow(Vendors::Cartesia::Actions::ListVoices).to receive(:call).and_return(live)
      allow(VideoConfig).to receive(:instance).and_return(VideoConfig.new(default_voice_id: 'the_default'))
      expect(described_class.resolve_or_default('nope')).to eq('the_default')

      allow(VideoConfig).to receive(:instance).and_return(VideoConfig.new)
      expect(described_class.resolve_or_default(nil)).to eq('live_fem') # first live voice → zero-config
    end

    it 'is nil when there are no voices at all (feature off)' do
      allow(Vendors::Cartesia::Actions::ListVoices).to receive(:call).and_return([])
      allow(VideoConfig).to receive(:instance).and_return(VideoConfig.new)
      expect(described_class.resolve_or_default('x')).to be_nil
    end
  end
end
