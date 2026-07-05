# frozen_string_literal: true

require 'rails_helper'

# Changing the LOCKED identity re-renders every scene with the new look; merges
# onto the current identity (untouched fields stay).
RSpec.describe Operations::Video::SetIdentity do
  let(:user) { User.create!(email: 'id@agencios.app', password: 'secret123', name: 'Id') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:ticket) do
    Operations::Tickets::Create.call(workspace: workspace, user: user,
                                     params: { project_id: project.id, title: 'Reel', creative_type: 'ugc_video', channels: %w[instagram] })
  end
  let(:creative) do
    Operations::Creatives::Create.call(ticket: ticket, creative_type: 'ugc_video',
                                       source: :generated, status: :ready, provider: 'openrouter')
  end
  let(:generation) do
    workspace.generations.create!(user: user, creative: creative, kind: :video, status: :completed, provider: 'openrouter',
                                  params: { mode: 'avatar', identity: { 'has_character' => true, 'character' => 'a fox', 'wardrobe' => 'suit' } })
  end
  let(:scene) do
    Operations::Video::Scenes::Create.call(creative: creative, position: 0, mode: 'avatar',
                                           prompt: 'p0', duration_seconds: 8, aspect_ratio: '9:16')
                                     .tap { |s| s.update!(render_state: :ready) }
  end

  before do
    Current.workspace = workspace
    Current.actor = user
    Operations::Credits::EnsureWallet.call(workspace: workspace).update!(purchased_balance: 100)
    allow(Vendors::OpenRouter::Actions::GenerateVideo).to receive(:call).and_return('job_id')
    generation && scene
  end

  after { Current.reset }

  it 'merges the changed fields, keeps the rest, re-renders all scenes, and charges' do
    expect do
      described_class.call(creative: creative, changes: { 'wardrobe' => 'casual hoodie', 'scenario' => 'a park' })
    end.to change { workspace.credit_transactions.debits.count }.by(1)

    id = generation.reload.params['identity']
    expect(id).to include('character' => 'a fox',        # untouched
                          'wardrobe' => 'casual hoodie',  # changed
                          'scenario' => 'a park')         # added
    expect(scene.reload.render_state).to eq('rendering')
    expect(creative.reload.status).to eq('generating')
  end

  it 'refuses while scenes are still rendering' do
    scene.update!(render_state: :rendering)
    expect { described_class.call(creative: creative, changes: { 'style' => 'noir' }) }
      .to raise_error(Operations::Errors::Invalid, /Espere as cenas/)
  end
end
