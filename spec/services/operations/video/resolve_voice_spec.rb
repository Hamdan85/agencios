# frozen_string_literal: true

require 'rails_helper'

# Resolves the orchestrator's voice pick into the generation params (one fixed
# voice_id for the whole video), or {} when no voice is configured (degrades to
# the model's native audio).
RSpec.describe Operations::Video::ResolveVoice do
  before do
    allow(VideoConfig).to receive(:instance).and_return(
      VideoConfig.new(voice_catalog: { 'Feminina BR' => 'voice_abc' }, default_voice_id: 'voice_default')
    )
    # Offline: no live Cartesia voices → resolution falls to the admin catalog.
    allow(Vendors::Cartesia::Actions::ListVoices).to receive(:call).and_return([])
  end

  it 'resolves a catalog label to its voice_id + keeps the label + valid speed' do
    out = described_class.call(spec: { 'voice' => 'Feminina BR', 'speed' => 'fast' })
    expect(out).to eq('voice_id' => 'voice_abc', 'voice_label' => 'Feminina BR', 'voice_speed' => 'fast')
  end

  it 'accepts a raw voice_id already in the catalog' do
    out = described_class.call(spec: { 'voice' => 'voice_abc' })
    expect(out['voice_id']).to eq('voice_abc')
  end

  it 'falls back to the default voice_id when the pick is blank/unknown' do
    expect(described_class.call(spec: {})['voice_id']).to eq('voice_default')
    expect(described_class.call(spec: { 'voice' => 'inexistente' })['voice_id']).to eq('voice_default')
  end

  it 'drops an invalid speed' do
    expect(described_class.call(spec: { 'voice' => 'Feminina BR', 'speed' => 'turbo' })).not_to have_key('voice_speed')
  end

  it 'returns {} when there is no catalog and no default (feature off)' do
    allow(VideoConfig).to receive(:instance).and_return(VideoConfig.new)
    expect(described_class.call(spec: { 'voice' => 'Feminina BR' })).to eq({})
  end
end
