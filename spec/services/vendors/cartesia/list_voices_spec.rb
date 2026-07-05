# frozen_string_literal: true

require 'rails_helper'

# The live Cartesia voice library lookup: cached, never-raises, [] when
# unconfigured or on error (the pipeline degrades to the model's native audio).
RSpec.describe Vendors::Cartesia::Actions::ListVoices do
  around do |example|
    store = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = store
  end

  it 'returns [] when Cartesia is not configured' do
    allow_any_instance_of(Vendors::Cartesia::Client).to receive(:configured?).and_return(false)
    expect(described_class.call).to eq([])
  end

  it 'returns the client voices and caches a non-empty result' do
    client = instance_double(Vendors::Cartesia::Client, configured?: true)
    allow(Vendors::Cartesia::Client).to receive(:new).and_return(client)
    voices = [{ id: 'v1', name: 'Ana', description: '', language: 'pt', gender: 'female' }]
    allow(client).to receive(:voices).with(language: 'pt').and_return(voices).once

    expect(described_class.call).to eq(voices)
    expect(described_class.call).to eq(voices) # served from cache — client hit once
  end

  it 'never raises and does NOT cache an error (so a transient failure recovers)' do
    client = instance_double(Vendors::Cartesia::Client, configured?: true)
    allow(Vendors::Cartesia::Client).to receive(:new).and_return(client)
    allow(client).to receive(:voices).and_raise(Vendors::Base::ServerError.new('boom'))

    expect(described_class.call).to eq([])
  end
end
