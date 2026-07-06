# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Ticket update — contextual fields', type: :request do
  include ActiveJob::TestHelper

  before do
    ActiveJob::Base.queue_adapter = :test
    @user, @workspace = Operations::Users::Register.call(
      email: 'owner@agencios.app', password: 'secret123', name: 'Owner', workspace_name: 'Ag'
    )
    Current.reset
    activate_billing(@workspace)
    post '/api/v1/session', params: { email: 'owner@agencios.app', password: 'secret123' }, as: :json
  end

  it 'saves fields and enqueues the cascade job (regression: bare Tickets:: constant)' do
    client = @workspace.clients.create!(name: 'C')
    project = @workspace.projects.create!(client: client, name: 'P', status: :active)
    ticket = @workspace.tickets.create!(project: project, status: :ideation)

    expect do
      patch "/api/v1/tickets/#{ticket.id}",
            params: { ticket: { status: 'ideation', fields: { brief: 'Nova brief' } } }, as: :json
    end.to have_enqueued_job(::Tickets::CascadeFieldsJob)

    expect(response).to have_http_status(:ok)
  end
end
