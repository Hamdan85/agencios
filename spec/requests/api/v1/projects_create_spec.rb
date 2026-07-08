# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Project creation', type: :request do
  before do
    @user, @workspace = Operations::Users::Register.call(
      email: 'owner@agencios.app', password: 'secret123', name: 'Owner', workspace_name: 'Talk Agency'
    )
    Current.reset
    activate_billing(@workspace)
    @client = @workspace.clients.create!(name: 'Acme')
  end

  def login
    post '/api/v1/session', params: { email: 'owner@agencios.app', password: 'secret123' }, as: :json
    expect(response).to have_http_status(:ok)
  end

  it 'creates a project with sanitized config settings' do
    login

    post '/api/v1/projects', params: {
      project: {
        client_id: @client.id, name: 'Summer',
        settings: {
          require_client_approval: false,
          auto_publish_after_approval: true,
          posting_window: { weekdays: [1, 3], times: ['09:00', '13:30'], min_gap_minutes: 90 },
          ignored_key: 'nope'
        }
      }
    }, as: :json

    expect(response).to have_http_status(:created).or have_http_status(:ok)
    project = @workspace.projects.find_by!(name: 'Summer')
    expect(project.settings['require_client_approval']).to be(false)
    expect(project.settings['auto_publish_after_approval']).to be(true)
    expect(project.settings['posting_window']['weekdays']).to eq([1, 3])
    expect(project.settings['posting_window']['times']).to eq(['09:00', '13:30'])
    expect(project.settings).not_to have_key('ignored_key')
  end

  it 'creates a project without settings (defaults resolve)' do
    login

    post '/api/v1/projects', params: {
      project: { client_id: @client.id, name: 'Bare' }
    }, as: :json

    expect(response).to have_http_status(:created).or have_http_status(:ok)
    project = @workspace.projects.find_by!(name: 'Bare')
    expect(project.settings).to eq({})
    expect(project.resolved_settings['require_client_approval']).to be(true)
  end
end
