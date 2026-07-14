# frozen_string_literal: true

require 'rails_helper'

# The internal-admin AI configuration: one "AI (models)" menu grouping the three
# singleton configs — Text (AiConfig), Image (ImageConfig), Video (VideoConfig) —
# with the voices page nested inside Video (no menu entry of its own; reached
# from the Video form's link).
RSpec.describe 'Admin AI config pages', type: :request do
  before do
    user, _workspace = Operations::Users::Register.call(
      email: 'staff@agencios.app', password: 'secret123', name: 'Staff', workspace_name: 'HQ'
    )
    Current.reset
    user.update!(staff: true)
  end

  def login
    post '/api/v1/session', params: { email: 'staff@agencios.app', password: 'secret123' }, as: :json
    expect(response).to have_http_status(:ok)
  end

  it 'each config index bounces to its singleton edit form and renders' do
    login
    { '/admin/ai_configs'    => AiConfig,
      '/admin/image_configs' => ImageConfig,
      '/admin/video_configs' => VideoConfig }.each do |path, klass|
      get path
      expect(response).to have_http_status(:redirect), "expected #{path} to redirect, got #{response.status}"
      follow_redirect!
      expect(response).to have_http_status(:ok), "expected #{path} edit to render, got #{response.status}"
      expect(klass.count).to eq(1)
    end
  end

  it 'saves the image model and the vendor picks it up' do
    login
    cfg = ImageConfig.first_or_create!
    put "/admin/image_configs/#{cfg.id}", params: { image_config: { default_model: 'x/new-image-model' } }
    expect(cfg.reload.default_model).to eq('x/new-image-model')
    client = Vendors::OpenRouter::Image.new(api_key: 'k')
    expect(client.instance_variable_get(:@model)).to eq('x/new-image-model')
  end

  it 'keeps the voices page reachable (linked from the Video config)' do
    login
    get '/admin/vozes'
    expect(response).to have_http_status(:ok)
  end

  it 'bounces non-staff users' do
    Operations::Users::Register.call(
      email: 'member@agencios.app', password: 'secret123', name: 'M', workspace_name: 'W'
    )
    Current.reset
    post '/api/v1/session', params: { email: 'member@agencios.app', password: 'secret123' }, as: :json
    get '/admin/image_configs'
    expect(response).to redirect_to('/')
  end
end
