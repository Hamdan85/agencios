# frozen_string_literal: true

require 'rails_helper'

# Destroying a post is CANCELING a not-yet-live publication — a post already on
# the network must be unpublished instead (its record and metrics survive).
RSpec.describe Controllers::Posts::Destroy do
  let(:user) { User.create!(email: 'cancel@agencios.app', password: 'secret123', name: 'Can') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:ticket) do
    Operations::Tickets::Create.call(
      workspace: workspace, user: user, params: { project_id: project.id, title: 'T', channels: %w[instagram] }
    )
  end

  before do
    allow(Broadcaster).to receive(:ticket)
    allow(Broadcaster).to receive(:board)
    Current.workspace = workspace
    Current.membership = workspace.memberships.find_by(user: user)
  end

  after { Current.reset }

  def build_post(status)
    account = client.social_accounts.find_by(provider: 'instagram') ||
              client.social_accounts.create!(workspace: workspace, provider: 'instagram')
    Post.create!(workspace: workspace, ticket: ticket, social_account: account,
                 status: status, scheduled_at: 1.day.from_now)
  end

  it 'cancels a scheduled post (deletes it before going live)' do
    post = build_post(:scheduled)
    params = ActionController::Parameters.new(ticket_id: ticket.id, id: post.id)

    described_class.call(params: params)

    expect(Post.exists?(post.id)).to be(false)
  end

  it 'cancels a failed post' do
    post = build_post(:failed)
    params = ActionController::Parameters.new(ticket_id: ticket.id, id: post.id)

    described_class.call(params: params)

    expect(Post.exists?(post.id)).to be(false)
  end

  it 'refuses to destroy a published post (unpublish is the way off the network)' do
    post = build_post(:published)
    params = ActionController::Parameters.new(ticket_id: ticket.id, id: post.id)

    expect { described_class.call(params: params) }.to raise_error(Operations::Errors::Invalid)
    expect(Post.exists?(post.id)).to be(true)
  end
end
