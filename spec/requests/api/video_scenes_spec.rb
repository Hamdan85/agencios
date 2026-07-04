# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Video scenes API', type: :request do
  before do
    ActiveJob::Base.queue_adapter = :test
    @user, @workspace = Operations::Users::Register.call(
      email: 'sc@agencios.app', password: 'secret123', name: 'Sc', workspace_name: 'Scene Agency'
    )
    Current.reset
    activate_billing(@workspace)

    Current.workspace = @workspace
    Current.actor = @user
    @client = @workspace.clients.create!(name: 'ACME')
    @project = @workspace.projects.create!(client: @client, name: 'Camp', color: '#7C3AED')
    @ticket = Operations::Tickets::Create.call(
      workspace: @workspace, user: @user,
      params: { project_id: @project.id, title: 'Reel', creative_type: 'ugc_video', channels: %w[instagram] }
    )
    @creative = Operations::Creatives::Create.call(
      ticket: @ticket, creative_type: 'ugc_video', source: :generated, status: :ready, provider: 'openrouter'
    )
    @workspace.generations.create!(user: @user, creative: @creative, kind: :video, status: :completed,
                                   provider: 'openrouter', params: { mode: 'avatar' })
    @scene = Operations::Video::Scenes::Create.call(
      creative: @creative, position: 0, mode: 'avatar', prompt: 'original', caption: 'Oi',
      duration_seconds: 8, aspect_ratio: '9:16'
    )
    @scene.update!(render_state: :ready, seed: 's1')
    Current.reset

    post '/api/v1/session', params: { email: 'sc@agencios.app', password: 'secret123' }, as: :json
    expect(response).to have_http_status(:ok)
  end

  it 'lists a video creative\'s scenes in order' do
    get "/api/v1/creatives/#{@creative.id}/scenes", as: :json
    expect(response).to have_http_status(:ok)
    scenes = JSON.parse(response.body)['scenes']
    expect(scenes.size).to eq(1)
    expect(scenes.first).to include('position' => 0, 'render_state' => 'ready', 'caption' => 'Oi')
  end

  it 'edits a caption for free (no render, no credits)' do
    expect do
      patch "/api/v1/video_scenes/#{@scene.id}", params: { scene: { caption: 'Nova' } }, as: :json
    end.not_to change { @workspace.credit_transactions.count }
    expect(response).to have_http_status(:ok)
    expect(@scene.reload.caption).to eq('Nova')
  end

  it 're-renders one scene on a prompt change (charged) and reopens the generation' do
    credit_workspace(@workspace, 50)
    allow(Vendors::OpenRouter::Actions::GenerateVideo).to receive(:call).and_return('job_re')

    patch "/api/v1/video_scenes/#{@scene.id}", params: { scene: { prompt: 'novo prompt do produto' } }, as: :json

    expect(response).to have_http_status(:ok)
    expect(@scene.reload.render_state).to eq('rendering')
    expect(@creative.generation.reload.status).to eq('processing')
  end
end
