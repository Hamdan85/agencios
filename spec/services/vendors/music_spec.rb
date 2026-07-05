# frozen_string_literal: true

require 'rails_helper'

# The music-provider adapter seam: resolves the admin-selected provider and
# delegates the shared search contract to its action.
RSpec.describe Vendors::Music do
  it 'defaults to Jamendo and delegates the search contract' do
    allow(VideoConfig).to receive(:instance).and_return(VideoConfig.new)
    allow(Vendors::Jamendo::Actions::SearchTracks).to receive(:call).and_return({ url: 'https://j/t.mp3' })

    out = described_class.search(query: 'calm piano', tags: 'calm', instrumental: true)

    expect(described_class.provider_key).to eq('jamendo')
    expect(Vendors::Jamendo::Actions::SearchTracks).to have_received(:call)
      .with(query: 'calm piano', tags: 'calm', instrumental: true)
    expect(out).to eq(url: 'https://j/t.mp3')
  end

  it 'routes to Epidemic Sound when that provider is selected' do
    allow(VideoConfig).to receive(:instance).and_return(VideoConfig.new(music_provider: 'epidemic_sound'))
    allow(Vendors::EpidemicSound::Actions::SearchTracks).to receive(:call).and_return(nil)

    described_class.search(query: 'x')

    expect(described_class.provider_key).to eq('epidemic_sound')
    expect(Vendors::EpidemicSound::Actions::SearchTracks).to have_received(:call)
  end

  it 'falls back to the default for an unknown provider key' do
    allow(VideoConfig).to receive(:instance).and_return(VideoConfig.new(music_provider: 'spotify'))
    expect(described_class.provider_key).to eq('jamendo')
  end
end
