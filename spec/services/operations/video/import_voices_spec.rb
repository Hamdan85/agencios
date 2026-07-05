# frozen_string_literal: true

require 'rails_helper'

# Imports the Cartesia voice library into the admin catalog so voices are visible
# + selectable in the internal admin.
RSpec.describe Operations::Video::ImportVoices do
  let(:voices) do
    [{ id: 'v_bruno', name: 'Bruno - Reliable Communicator', gender: 'masculine', country: 'BR', language: 'pt' },
     { id: 'v_isa', name: 'Isabella - Warm Storyteller', gender: 'feminine', country: 'BR', language: 'pt' }]
  end

  before { VideoConfig.delete_all }

  it 'writes every voice into the catalog and sets a default when none is set' do
    client = instance_double(Vendors::Cartesia::Client, configured?: true)
    allow(Vendors::Cartesia::Client).to receive(:new).and_return(client)
    allow(client).to receive(:voices).with(language: 'pt').and_return(voices)

    count = described_class.call

    expect(count).to eq(2)
    cfg = VideoConfig.instance
    expect(cfg.voices).to eq('Bruno - Reliable Communicator' => 'v_bruno',
                             'Isabella - Warm Storyteller' => 'v_isa')
    expect(cfg.default_voice_id).to eq('v_bruno') # first (BR) becomes the default
  end

  it 'keeps an existing default and merges with prior catalog entries' do
    VideoConfig.create!(voice_catalog: { 'Marca' => 'custom' }, default_voice_id: 'custom')
    client = instance_double(Vendors::Cartesia::Client, configured?: true)
    allow(Vendors::Cartesia::Client).to receive(:new).and_return(client)
    allow(client).to receive(:voices).and_return(voices)

    described_class.call

    cfg = VideoConfig.instance
    expect(cfg.voices).to include('Marca' => 'custom', 'Bruno - Reliable Communicator' => 'v_bruno')
    expect(cfg.default_voice_id).to eq('custom') # untouched
  end

  it 'returns 0 (no-op) when Cartesia is not configured' do
    allow_any_instance_of(Vendors::Cartesia::Client).to receive(:configured?).and_return(false)
    expect(described_class.call).to eq(0)
  end
end
