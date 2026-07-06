# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Posts index', type: :request do
  before do
    @user, @workspace = Operations::Users::Register.call(
      email: 'owner@agencios.app', password: 'secret123', name: 'Owner', workspace_name: 'Ag'
    )
    Current.reset
    activate_billing(@workspace)
    post '/api/v1/session', params: { email: 'owner@agencios.app', password: 'secret123' }, as: :json
  end

  def seed
    client = @workspace.clients.create!(name: 'C')
    project = @workspace.projects.create!(client: client, name: 'P', status: :active)
    ticket = @workspace.tickets.create!(project: project, status: :published)
    ig = SocialAccount.create!(workspace: @workspace, client: client, provider: :instagram)
    tk = SocialAccount.create!(workspace: @workspace, client: client, provider: :tiktok)
    Post.create!(workspace: @workspace, ticket: ticket, social_account: ig, status: :published, published_at: Time.current)
    Post.create!(workspace: @workspace, ticket: ticket, social_account: tk, status: :scheduled, scheduled_at: 1.day.from_now)
  end

  it 'filters workspace posts by provider' do
    seed
    get '/api/v1/posts', params: { providers: ['instagram'] }
    body = JSON.parse(response.body)
    expect(response).to have_http_status(:ok)
    expect(body['posts'].map { |p| p['provider'] }).to eq(['instagram'])
  end

  it 'filters by status' do
    seed
    get '/api/v1/posts', params: { status: ['scheduled'] }
    body = JSON.parse(response.body)
    expect(body['posts'].map { |p| p['status'] }).to eq(['scheduled'])
  end

  it 'keeps per-ticket behavior when ticket_id is present' do
    seed
    ticket = @workspace.tickets.first
    get "/api/v1/tickets/#{ticket.id}/posts"
    body = JSON.parse(response.body)
    expect(response).to have_http_status(:ok)
    expect(body['posts'].size).to eq(2)
  end
end
