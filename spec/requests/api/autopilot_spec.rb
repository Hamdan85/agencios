# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Autopilot (GO mode) API', type: :request do
  before do
    ActiveJob::Base.queue_adapter = :test
    @user, @workspace = Operations::Users::Register.call(
      email: 'go@agencios.app', password: 'secret123', name: 'Go', workspace_name: 'Go Agency'
    )
    Current.reset
    activate_billing(@workspace)

    Current.workspace = @workspace
    Current.actor = @user
    @client = @workspace.clients.create!(name: 'ACME')
    @project = @workspace.projects.create!(client: @client, name: 'Camp', color: '#7C3AED')
    @ticket = build_ticket(%w[feed_image carousel])
    Current.reset

    post '/api/v1/session', params: { email: 'go@agencios.app', password: 'secret123' }, as: :json
    expect(response).to have_http_status(:ok)
  end

  def build_ticket(types)
    t = Operations::Tickets::Create.call(
      workspace: @workspace, user: @user, params: { project_id: @project.id, title: 'T', channels: %w[instagram] }
    )
    Operations::Tickets::UpdateFields.call(ticket: t, status: 'scoping', values: { 'creative_types' => types })
    t.reload
  end

  it 'returns a credit estimate for a ticket GO' do
    post "/api/v1/tickets/#{@ticket.id}/autopilot_estimate", as: :json

    expect(response).to have_http_status(:ok)
    est = JSON.parse(response.body)['estimate']
    expect(est['eligible']).to be(true)
    expect(est['total_credits']).to eq(1) # feed_image(1) + carousel(0)
  end

  it 'blocks the start with 402 when the wallet is short of the estimate' do
    video = build_ticket(%w[ugc_video]) # needs 16 credits, wallet empty

    post "/api/v1/tickets/#{video.id}/autopilot_start", params: { mode: 'scheduled' }, as: :json

    expect(response).to have_http_status(:payment_required)
    body = JSON.parse(response.body)
    expect(body['code']).to eq('insufficient_credits')
    expect(body['required']).to eq(16)
  end

  it 'launches a run when credits cover the estimate' do
    credit_workspace(@workspace, 50)

    post "/api/v1/tickets/#{@ticket.id}/autopilot_start", params: { mode: 'scheduled' }, as: :json

    expect(response).to have_http_status(:ok)
    run = JSON.parse(response.body)['run']
    expect(run['state']).to eq('pending')
    expect(@ticket.reload.autopilot_runs.count).to eq(1)
  end

  it 'exposes the live batch progress on the project show while GO runs' do
    credit_workspace(@workspace, 50)
    post "/api/v1/projects/#{@project.id}/autopilot_start", params: { mode: 'scheduled' }, as: :json
    expect(response).to have_http_status(:ok)

    get "/api/v1/projects/#{@project.id}", as: :json
    expect(response).to have_http_status(:ok)
    ap = JSON.parse(response.body)['autopilot']
    expect(ap).to be_present
    expect(ap['active']).to be(true)
    expect(ap['total']).to eq(1)
    expect(ap['done']).to eq(0)
  end

  it 'drops the batch progress once the run reaches a terminal state' do
    credit_workspace(@workspace, 50)
    post "/api/v1/projects/#{@project.id}/autopilot_start", params: { mode: 'scheduled' }, as: :json
    batch = AutopilotRun.batches.last
    batch.update!(state: 'completed', finished_at: Time.current)

    get "/api/v1/projects/#{@project.id}", as: :json
    expect(JSON.parse(response.body)['autopilot']).to be_nil
  end

  it 'blocks a project GO (422) when a ticket needs manual creatives' do
    build_ticket(%w[cover]) # not auto-generatable
    credit_workspace(@workspace, 50)

    post "/api/v1/projects/#{@project.id}/autopilot_start", params: { mode: 'scheduled' }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)['error']).to match(/criativos manuais/)
  end
end
