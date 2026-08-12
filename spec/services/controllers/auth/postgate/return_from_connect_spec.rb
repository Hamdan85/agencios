# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Controllers::Auth::Postgate::ReturnFromConnect do
  let(:user) { User.create!(email: "pgreturn-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'PG') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client_record) { workspace.clients.create!(name: 'ACME', postgate_group_id: 'grp_1') }
  let(:pg_client) { instance_double(Vendors::Postgate::Client) }

  before { allow(Vendors::Postgate::Client).to receive(:new).and_return(pg_client) }

  def signed_state(network: 'instagram', link: nil, client: client_record)
    Rails.application.message_verifier('agencios:social_connect').generate(
      { 'client_id' => client.id, 'network' => network, 'link' => link }, expires_in: 1.hour
    )
  end

  def profile(id:, platform_account_id:, display_name: 'acme')
    {
      'id' => id, 'platform_account_id' => platform_account_id, 'display_name' => display_name,
      'avatar_url' => 'https://cdn.example/a.png', 'status' => 'connected', 'scopes' => ['publish'],
      'created_at' => '2026-08-12T00:00:00Z'
    }
  end

  it 'persists a postgate SocialAccount, merged onto a pre-existing direct row (instagram)' do
    existing = client_record.social_accounts.create!(
      workspace: workspace, provider: 'instagram', ig_user_id: 'ig_123',
      connection_source: :direct, status: :connected
    )
    allow(pg_client).to receive(:list_profiles)
      .with(profile_group_id: 'grp_1', platform: 'instagram')
      .and_return({ 'data' => [profile(id: 'prof_1', platform_account_id: 'ig_123')] })

    result = described_class.call(state: signed_state, params: {})

    expect(result).to eq(client_id: client_record.id, network: 'instagram', link: nil)
    existing.reload
    expect(existing).to be_connection_source_postgate
    expect(existing.postgate_profile_id).to eq('prof_1')
    expect(existing.ig_user_id).to eq('ig_123')
    expect(existing.username).to eq('acme')
    expect(existing.avatar_url).to eq('https://cdn.example/a.png')
    expect(existing.scopes).to eq(['publish'])
    # merged onto the same row — no duplicate created
    expect(client_record.social_accounts.where(provider: 'instagram').count).to eq(1)
  end

  it 'picks the newest connected profile when several are returned' do
    allow(pg_client).to receive(:list_profiles)
      .with(profile_group_id: 'grp_1', platform: 'x')
      .and_return({ 'data' => [
        profile(id: 'prof_old', platform_account_id: 'x_old').merge('created_at' => '2026-01-01T00:00:00Z'),
        profile(id: 'prof_new', platform_account_id: 'x_new').merge('created_at' => '2026-06-01T00:00:00Z')
      ] })

    described_class.call(state: signed_state(network: 'x'), params: {})

    account = client_record.social_accounts.find_by(provider: 'x')
    expect(account.postgate_profile_id).to eq('prof_new')
  end

  it 'carries the public-connect link token through to the result' do
    allow(pg_client).to receive(:list_profiles)
      .with(profile_group_id: 'grp_1', platform: 'threads')
      .and_return({ 'data' => [profile(id: 'prof_3', platform_account_id: 'th_1')] })

    result = described_class.call(state: signed_state(network: 'threads', link: 'tok_abc'), params: {})

    expect(result).to eq(client_id: client_record.id, network: 'threads', link: 'tok_abc')
  end

  it 'raises on a connection_error param (the controller maps this to an error redirect)' do
    expect do
      described_class.call(state: signed_state, params: { connection_error: 'access_denied' })
    end.to raise_error(Vendors::Base::Error)
  end

  it 'raises Operations::Errors::Invalid on a bad/expired state' do
    expect do
      described_class.call(state: 'not-a-real-token', params: {})
    end.to raise_error(Operations::Errors::Invalid)
  end

  it 'raises when no connected profile can be found' do
    allow(pg_client).to receive(:list_profiles)
      .with(profile_group_id: 'grp_1', platform: 'facebook')
      .and_return({ 'data' => [] })

    expect do
      described_class.call(state: signed_state(network: 'facebook'), params: {})
    end.to raise_error(Vendors::Base::Error)
  end

  it 'captures the first pinterest board id into postgate_meta' do
    allow(pg_client).to receive(:list_profiles)
      .with(profile_group_id: 'grp_1', platform: 'pinterest')
      .and_return({ 'data' => [profile(id: 'prof_pin', platform_account_id: 'pin_1', display_name: 'acme pins')] })
    allow(pg_client).to receive(:list_boards).with('prof_pin')
      .and_return({ 'data' => [{ 'id' => 'board_1', 'name' => 'Main' }] })

    described_class.call(state: signed_state(network: 'pinterest'), params: {})

    account = client_record.social_accounts.find_by(provider: 'pinterest')
    expect(account.postgate_meta).to eq('board_id' => 'board_1')
  end

  it 'does not blow up when the pinterest board fetch fails (best-effort)' do
    allow(pg_client).to receive(:list_profiles)
      .with(profile_group_id: 'grp_1', platform: 'pinterest')
      .and_return({ 'data' => [profile(id: 'prof_pin2', platform_account_id: 'pin_2')] })
    allow(pg_client).to receive(:list_boards).with('prof_pin2')
      .and_raise(Vendors::Base::ServerError.new('down'))

    expect do
      described_class.call(state: signed_state(network: 'pinterest'), params: {})
    end.not_to raise_error

    account = client_record.social_accounts.find_by(provider: 'pinterest')
    expect(account.postgate_meta).to eq({})
  end
end
