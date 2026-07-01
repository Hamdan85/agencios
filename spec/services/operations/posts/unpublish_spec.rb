# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Posts::Unpublish do
  let(:user) { User.create!(email: 'unpub@agencios.app', password: 'secret123', name: 'Unpub') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:ticket) do
    Operations::Tickets::Create.call(
      workspace: workspace, user: user, params: { project_id: project.id, title: 'T', channels: %w[facebook] }
    ).tap { |t| Operations::Tickets::ChangeStatus.call(t, 'published', user: user, force: true) }
  end

  before do
    allow(Broadcaster).to receive(:ticket)
    Current.workspace = workspace
  end

  after { Current.reset }

  def build_post(provider)
    account = client.social_accounts.create!(workspace: workspace, provider: provider)
    Post.create!(
      workspace: workspace, ticket: ticket, social_account: account,
      status: :published, published_at: Time.current, external_post_id: 'ext-1'
    )
  end

  it 'raises when the post is not published' do
    post = build_post('facebook')
    post.update!(status: :scheduled)

    expect { described_class.call(post: post, user: user) }.to raise_error(Operations::Errors::Invalid)
  end

  it 'deletes the post on the network and marks it unpublished, without a manual-removal note' do
    post = build_post('facebook')
    allow(Vendors::Meta::Client).to receive(:new).and_return(instance_double(Vendors::Meta::Client, delete: {}))

    described_class.call(post: post, user: user)

    expect(post.reload).to be_status_unpublished
    expect(post.unpublished_at).to be_present
    expect(post.failure_reason).to be_nil
  end

  it 'falls back to a local unpublish with a manual-removal note when the network has no delete API' do
    post = build_post('tiktok')

    described_class.call(post: post, user: user)

    expect(post.reload).to be_status_unpublished
    expect(post.failure_reason).to be_present
  end

  it 'reverts the ticket to scheduled once no post remains published' do
    post = build_post('tiktok')
    expect(ticket.status).to eq('published')

    described_class.call(post: post, user: user)

    expect(ticket.reload.status).to eq('scheduled')
  end

  it 'keeps the ticket published when another post is still live' do
    post = build_post('tiktok')
    build_post('facebook') # a second, still-published post on another channel

    described_class.call(post: post, user: user)

    expect(ticket.reload.status).to eq('published')
  end
end
