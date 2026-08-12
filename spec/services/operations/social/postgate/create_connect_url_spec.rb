# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Social::Postgate::CreateConnectUrl do
  let(:user) { User.create!(email: "pgconnecturl-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'PG') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client_record) { workspace.clients.create!(name: 'ACME') }
  let(:pg_client) { instance_double(Vendors::Postgate::Client) }

  it 'creates a profile group once, persists it, and builds the return_url from the given state' do
    expect(pg_client).to receive(:create_profile_group)
      .with(name: 'ACME', timezone: Time.zone.name)
      .and_return({ 'id' => 'grp_1' })
    expect(pg_client).to receive(:create_connect_url).with(
      platform: 'instagram', profile_group_id: 'grp_1',
      return_url: "#{SystemConfig.app_host}/auth/postgate/return?state=signed-state-abc",
      instance_url: nil
    ).and_return({ 'url' => 'https://connect.postgate.studio/x', 'expires_in' => 600, 'platform' => 'instagram' })

    result = described_class.call(
      client: client_record, network: 'instagram', state: 'signed-state-abc', api_client: pg_client
    )

    expect(result).to eq(url: 'https://connect.postgate.studio/x')
    expect(client_record.reload.postgate_group_id).to eq('grp_1')
  end

  it 'reuses an existing profile group instead of creating a new one' do
    client_record.update!(postgate_group_id: 'grp_existing')
    expect(pg_client).not_to receive(:create_profile_group)
    expect(pg_client).to receive(:create_connect_url)
      .with(hash_including(profile_group_id: 'grp_existing'))
      .and_return({ 'url' => 'https://x' })

    described_class.call(client: client_record, network: 'facebook', state: 's', api_client: pg_client)
  end

  it 'passes instance_url through untouched (mastodon)' do
    client_record.update!(postgate_group_id: 'grp_existing')
    expect(pg_client).to receive(:create_connect_url)
      .with(hash_including(platform: 'mastodon', instance_url: 'https://mastodon.social'))
      .and_return({ 'url' => 'https://x' })

    described_class.call(
      client: client_record, network: 'mastodon', state: 's',
      instance_url: 'https://mastodon.social', api_client: pg_client
    )
  end

  it 'defaults to a real Vendors::Postgate::Client when none is injected' do
    allow(Vendors::Postgate::Client).to receive(:new).and_return(pg_client)
    client_record.update!(postgate_group_id: 'grp_existing')
    expect(pg_client).to receive(:create_connect_url).and_return({ 'url' => 'https://x' })

    described_class.call(client: client_record, network: 'x', state: 's')
  end
end
