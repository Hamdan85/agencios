# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Post detail', type: :request do
  before do
    @user, @workspace = Operations::Users::Register.call(
      email: 'owner@agencios.app', password: 'secret123', name: 'Owner', workspace_name: 'Ag'
    )
    Current.reset
    activate_billing(@workspace)
    post '/api/v1/session', params: { email: 'owner@agencios.app', password: 'secret123' }, as: :json
  end

  it 'returns a workspace post with metric history' do
    client = @workspace.clients.create!(name: 'C')
    project = @workspace.projects.create!(client: client, name: 'P', status: :active)
    ticket = @workspace.tickets.create!(project: project, status: :published)
    acct = SocialAccount.create!(workspace: @workspace, client: client, provider: :instagram)
    post = Post.create!(workspace: @workspace, ticket: ticket, social_account: acct, status: :published, published_at: Time.current)
    post.post_metrics.create!(captured_at: 1.day.ago, views: 5)

    get "/api/v1/posts/#{post.id}"
    body = JSON.parse(response.body)
    expect(response).to have_http_status(:ok)
    expect(body['post']['id']).to eq(post.id)
    expect(body['post']['metric_history'].length).to eq(1)
  end

  it '404s for a post outside the workspace' do
    other = Workspace.create!(name: 'Other', slug: "ws-#{SecureRandom.hex(4)}")
    client = other.clients.create!(name: 'C')
    project = other.projects.create!(client: client, name: 'P', status: :active)
    ticket = other.tickets.create!(project: project, status: :published)
    acct = SocialAccount.create!(workspace: other, client: client, provider: :instagram)
    post = Post.create!(workspace: other, ticket: ticket, social_account: acct, status: :scheduled, scheduled_at: 1.day.from_now)

    get "/api/v1/posts/#{post.id}"
    expect(response).to have_http_status(:not_found)
  end
end
