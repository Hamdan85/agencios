# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Project settings', type: :request do
  before do
    @user, @workspace = Operations::Users::Register.call(
      email: 'owner@agencios.app', password: 'secret123', name: 'Owner', workspace_name: 'Talk Agency'
    )
    Current.reset
    activate_billing(@workspace)
  end

  def login
    post '/api/v1/session', params: { email: 'owner@agencios.app', password: 'secret123' }, as: :json
    expect(response).to have_http_status(:ok)
  end

  it 'updates and echoes resolved settings' do
    login
    client = @workspace.clients.create!(name: 'C')
    project = @workspace.projects.create!(client: client, name: 'P', status: :active)

    patch "/api/v1/projects/#{project.id}/settings",
          params: { settings: { require_client_approval: true, posting_window: { weekdays: [1, 2], times: ['10:00'] } } },
          as: :json

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['project']['settings']['require_client_approval']).to be(true)
    expect(body['project']['settings']['posting_window']['weekdays']).to eq([1, 2])
  end
end
