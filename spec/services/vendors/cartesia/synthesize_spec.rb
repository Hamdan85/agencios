# frozen_string_literal: true

require 'rails_helper'

# The Cartesia TTS action: synthesizes a line in a fixed voice, never raising to
# the caller (a missing voice must never fail a video render).
RSpec.describe Vendors::Cartesia::Actions::Synthesize do
  it 'returns nil (no synthesis) when Cartesia is not configured' do
    allow_any_instance_of(Vendors::Cartesia::Client).to receive(:configured?).and_return(false)

    expect(described_class.call(text: 'Olá', voice_id: 'v1')).to be_nil
  end

  it 'returns nil for a blank line or blank voice_id (nothing to synthesize)' do
    expect(described_class.call(text: '  ', voice_id: 'v1')).to be_nil
    expect(described_class.call(text: 'Olá', voice_id: '')).to be_nil
  end

  it 'returns the bytes + content type from the client on success' do
    client = instance_double(Vendors::Cartesia::Client, configured?: true)
    allow(Vendors::Cartesia::Client).to receive(:new).and_return(client)
    allow(client).to receive(:synthesize)
      .with(text: 'Olá', voice_id: 'v1', language: 'pt', speed: nil)
      .and_return({ bytes: 'AUDIO', content_type: 'audio/mpeg' })

    expect(described_class.call(text: 'Olá', voice_id: 'v1')).to eq(bytes: 'AUDIO', content_type: 'audio/mpeg')
  end

  it 'never raises — a client error degrades to nil' do
    client = instance_double(Vendors::Cartesia::Client, configured?: true)
    allow(Vendors::Cartesia::Client).to receive(:new).and_return(client)
    allow(client).to receive(:synthesize).and_raise(Vendors::Base::ServerError.new('boom'))

    expect(described_class.call(text: 'Olá', voice_id: 'v1')).to be_nil
  end
end
