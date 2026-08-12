# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Vendors::Postgate::Actions::PublishPost do
  let(:user) { User.create!(email: "pgpub-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'PG') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client_record) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client_record, name: 'Camp', color: '#7C3AED') }
  let(:ticket) do
    Operations::Tickets::Create.call(
      workspace: workspace, user: user, params: { project_id: project.id, title: 'T', channels: %w[pinterest] }
    )
  end
  let(:pg_client) { instance_double(Vendors::Postgate::Client) }

  before do
    Current.workspace = workspace
    allow(Vendors::Postgate::Client).to receive(:new).and_return(pg_client)
    allow(pg_client).to receive(:list_boards)
  end

  after { Current.reset }

  def build_account(provider, meta: {})
    client_record.social_accounts.create!(
      workspace: workspace, provider: provider, connection_source: :postgate,
      postgate_profile_id: 'prof_1', postgate_meta: meta
    )
  end

  def build_post(account, caption: 'Hello world')
    Post.create!(workspace: workspace, ticket: ticket, social_account: account,
                 status: :publishing, scheduled_at: 1.hour.ago, caption: caption)
  end

  def published_target(id: 'e', permalink: 'p')
    { 'status' => 'published', 'platform_post_id' => id, 'permalink' => permalink }
  end

  describe 'immediate publish' do
    it 'returns external_post_id/permalink/postgate_post_id once the target is published on the first poll' do
      account = build_account('instagram')
      post = build_post(account)
      allow(pg_client).to receive(:create_post).and_return({ 'id' => 'pg_1' })
      allow(pg_client).to receive(:get_post).with('pg_1').and_return(
        { 'id' => 'pg_1', 'targets' => [published_target(id: 'ext-1', permalink: 'https://x.test/1')] }
      )

      result = described_class.call(post)

      expect(result).to eq(external_post_id: 'ext-1', permalink: 'https://x.test/1', postgate_post_id: 'pg_1')
      expect(pg_client).to have_received(:create_post).with(
        hash_including(profiles: ['prof_1'], post: hash_including(body: 'Hello world')),
        idempotency_key: "agencios-#{post.id}-#{post.updated_at.to_i}"
      )
    end
  end

  describe 'pending' do
    it 'returns pending: true when the target never settles within the poll window' do
      account = build_account('instagram')
      post = build_post(account)
      allow(pg_client).to receive(:create_post).and_return({ 'id' => 'pg_2' })
      allow(pg_client).to receive(:get_post).with('pg_2').and_return(
        { 'id' => 'pg_2', 'targets' => [{ 'status' => 'publishing' }] }
      )
      action = described_class.new(post)
      allow(action).to receive(:sleep)

      result = action.call

      expect(result).to eq(pending: true, postgate_post_id: 'pg_2')
      expect(pg_client).to have_received(:get_post).exactly(5).times
    end
  end

  describe 'failed target' do
    it 'raises Vendors::Base::Error with the target error message' do
      account = build_account('instagram')
      post = build_post(account)
      allow(pg_client).to receive(:create_post).and_return({ 'id' => 'pg_3' })
      allow(pg_client).to receive(:get_post).with('pg_3').and_return(
        { 'id' => 'pg_3', 'targets' => [{ 'status' => 'failed', 'error_message' => 'token revoked' }] }
      )

      expect { described_class.call(post) }.to raise_error(Vendors::Base::Error, 'token revoked')
    end
  end

  describe 'pinterest board resolution' do
    it 'uses postgate_meta board_id when present, skipping list_boards' do
      account = build_account('pinterest', meta: { 'board_id' => 'board-configured' })
      post = build_post(account)
      allow(pg_client).to receive(:create_post).and_return({ 'id' => 'pg_4' })
      allow(pg_client).to receive(:get_post).and_return({ 'id' => 'pg_4', 'targets' => [published_target] })

      described_class.call(post)

      expect(pg_client).to have_received(:create_post).with(
        hash_including(post: hash_including(options: { pinterest: { board_id: 'board-configured' } })),
        idempotency_key: anything
      )
      expect(pg_client).not_to have_received(:list_boards)
    end

    it 'falls back to the first board from list_boards when no board_id is configured' do
      account = build_account('pinterest')
      post = build_post(account)
      allow(pg_client).to receive(:list_boards).with('prof_1')
                                                .and_return('data' => [{ 'id' => 'board-fallback', 'name' => 'Main' }])
      allow(pg_client).to receive(:create_post).and_return({ 'id' => 'pg_5' })
      allow(pg_client).to receive(:get_post).and_return({ 'id' => 'pg_5', 'targets' => [published_target] })

      described_class.call(post)

      expect(pg_client).to have_received(:create_post).with(
        hash_including(post: hash_including(options: { pinterest: { board_id: 'board-fallback' } })),
        idempotency_key: anything
      )
    end

    it 'raises when the account has no boards at all' do
      account = build_account('pinterest')
      post = build_post(account)
      allow(pg_client).to receive(:list_boards).with('prof_1').and_return('data' => [])

      expect { described_class.call(post) }.to raise_error(Vendors::Base::Error)
    end
  end

  describe 'youtube options' do
    it 'builds title/privacy/made_for_kids/community_guidelines_confirmed from the caption' do
      account = build_account('youtube')
      post = build_post(account, caption: "My great video\nMore text below the title")
      allow(pg_client).to receive(:create_post).and_return({ 'id' => 'pg_6' })
      allow(pg_client).to receive(:get_post).and_return({ 'id' => 'pg_6', 'targets' => [published_target] })

      described_class.call(post)

      expect(pg_client).to have_received(:create_post).with(
        hash_including(post: hash_including(options: {
                          youtube: { title: 'My great video', privacy: 'public', made_for_kids: false,
                                     community_guidelines_confirmed: true }
                        })),
        idempotency_key: anything
      )
    end
  end
end
