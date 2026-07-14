# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Ticket approval actions', type: :request do
  include ActiveJob::TestHelper

  before do
    ActiveJob::Base.queue_adapter = :test
    @user, @workspace = Operations::Users::Register.call(
      email: 'owner@agencios.app', password: 'secret123', name: 'Owner', workspace_name: 'Ag'
    )
    Current.reset
    activate_billing(@workspace)
  end

  def login
    post '/api/v1/session', params: { email: 'owner@agencios.app', password: 'secret123' }, as: :json
    expect(response).to have_http_status(:ok)
  end

  it 'sends it to approval, then approves internally' do
    login
    client = @workspace.clients.create!(name: 'C', email: 'c@c.co')
    project = @workspace.projects.create!(client: client, name: 'P', status: :active, settings: { 'auto_publish_after_approval' => false })
    ticket = @workspace.tickets.create!(project: project, status: :production, channels: ['instagram'])
    Creative.create!(workspace: @workspace, ticket: ticket, creative_type: 'carousel', status: :ready)

    ActionMailer::Base.deliveries.clear
    perform_enqueued_jobs do
      post "/api/v1/tickets/#{ticket.id}/request_approval", as: :json
    end
    expect(response).to have_http_status(:ok)
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(ticket.reload.status).to eq('approval') # the request IS the move

    post "/api/v1/tickets/#{ticket.id}/approve", as: :json
    expect(response).to have_http_status(:ok)
    expect(ticket.reload.fully_approved?).to be(true)
  end
end
