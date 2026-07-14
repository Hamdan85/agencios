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

  describe 'the model-picker endpoint (/admin/openrouter_models)' do
    def stub_catalog(models)
      catalog = instance_double(Vendors::OpenRouter::Catalog, models: models)
      allow(Vendors::OpenRouter::Catalog).to receive(:new).and_return(catalog)
    end

    it 'returns the searched catalog page as JSON' do
      login
      stub_catalog([{ id: 'google/gemini-3.1-flash-image', name: 'Gemini 3.1 Flash Image' }])
      get '/admin/openrouter_models', params: { kind: 'image', q: 'gemini' }
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['results']).to eq([{ 'id' => 'google/gemini-3.1-flash-image', 'name' => 'Gemini 3.1 Flash Image' }])
      expect(body['has_more']).to be(false)
    end

    it 'rejects an unknown kind' do
      login
      get '/admin/openrouter_models', params: { kind: 'audio' }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'answers 502 with an error body when OpenRouter is unreachable' do
      login
      allow(Vendors::OpenRouter::Catalog).to receive(:new).and_raise(Vendors::Base::ServerError.new('down', status: 503))
      get '/admin/openrouter_models', params: { kind: 'text' }
      expect(response).to have_http_status(:bad_gateway)
      expect(JSON.parse(response.body)['results']).to eq([])
    end

    it 'answers 401 JSON for non-staff' do
      get '/admin/openrouter_models', params: { kind: 'text' }
      expect(response).to have_http_status(:unauthorized)
    end
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
