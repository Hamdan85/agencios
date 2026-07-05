# frozen_string_literal: true

require 'rails_helper'

# Turns the orchestrator's music spec (search query + mix knobs) into concrete
# generation params: a resolved track from the catalog + clamped ffmpeg params.
RSpec.describe Operations::Video::ResolveMusic do
  it 'returns nothing when there is no query/mood' do
    expect(described_class.call(spec: {})).to eq({})
    expect(described_class.call(spec: nil)).to eq({})
  end

  it 'searches the active provider and carries the orchestrator mix params (clamped)' do
    allow(Vendors::Music).to receive(:search).and_return(
      { url: 'https://prov/t.mp3', title: 'Track', attribution: 'Track — Artist' }
    )

    out = described_class.call(spec: { 'query' => 'upbeat corporate', 'mood' => 'upbeat',
                                       'volume' => 5.0, 'fade_in' => 1.0, 'fade_out' => 2.0, 'duck' => true })

    expect(Vendors::Music).to have_received(:search).with(query: 'upbeat corporate', tags: 'upbeat')
    expect(out).to include('music_url' => 'https://prov/t.mp3', 'music_mood' => 'upbeat',
                           'music_volume' => 0.6, # clamped from 5.0
                           'music_fade_in' => 1.0, 'music_fade_out' => 2.0, 'music_duck' => true)
  end

  it 'falls back to the admin catalog when the provider finds nothing' do
    allow(Vendors::Music).to receive(:search).and_return(nil)
    allow(VideoConfig).to receive(:instance).and_return(
      VideoConfig.new(music_tracks: { 'calm' => { 'url' => 'https://cat/calm.mp3', 'title' => 'Calm' } })
    )

    out = described_class.call(spec: { 'mood' => 'calm' })
    expect(out['music_url']).to eq('https://cat/calm.mp3')
  end

  it 'no track anywhere → no music' do
    allow(Vendors::Music).to receive(:search).and_return(nil)
    allow(VideoConfig).to receive(:instance).and_return(VideoConfig.new)
    expect(described_class.call(spec: { 'mood' => 'epic' })).to eq({})
  end
end
