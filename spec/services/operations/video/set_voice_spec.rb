# frozen_string_literal: true

require 'rails_helper'

# Changing the fixed voice re-renders every scene (the voice is baked in via the
# lip-sync reference) and drops the old synthesized clips so they re-synthesize.
RSpec.describe Operations::Video::SetVoice do
  let(:user) { User.create!(email: 'sv@agencios.app', password: 'secret123', name: 'SV') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:ticket) do
    project = workspace.projects.create!(client: client, name: 'C', color: '#7C3AED')
    Operations::Tickets::Create.call(workspace: workspace, user: user,
                                     params: { project_id: project.id, title: 'Reel', creative_type: 'ugc_video', channels: %w[instagram] })
  end
  let(:creative) do
    Operations::Creatives::Create.call(ticket: ticket, creative_type: 'ugc_video',
                                       source: :generated, status: :ready, provider: 'openrouter')
  end
  let(:generation) do
    workspace.generations.create!(user: user, creative: creative, kind: :video, status: :completed,
                                  provider: 'openrouter', params: { mode: 'avatar', voice_id: 'old' })
  end

  before do
    Current.workspace = workspace
    Current.actor = user
    Operations::Credits::EnsureWallet.call(workspace: workspace).update!(purchased_balance: 10_000)
    allow(VideoConfig).to receive(:instance).and_return(
      VideoConfig.new(voice_catalog: { 'Feminina BR' => 'voice_new' })
    )
    # Offline: no live Cartesia voices → resolution uses the admin catalog.
    allow(Vendors::Cartesia::Actions::ListVoices).to receive(:call).and_return([])
    allow(Operations::Video::RenderScene).to receive(:call)
    generation # force creation now that Current.workspace is set
    2.times do |i|
      Operations::Video::Scenes::Create.call(creative: creative, position: i, mode: 'avatar',
                                             prompt: "p#{i}", duration_seconds: 8, aspect_ratio: '9:16')
                                       .tap { |s| s.update!(render_state: :ready) }
    end
  end

  after { Current.reset }

  it 'sets the new voice_id, charges, re-renders every scene, and clears old clips' do
    scenes = creative.video_scenes.ordered.to_a
    scenes.first.voice_clip.attach(io: StringIO.new('OLD'), filename: 'v.mp3', content_type: 'audio/mpeg')
    scenes.first.update!(metadata: { 'voice_fingerprint' => 'old' })

    expect { described_class.call(creative: creative, voice: 'Feminina BR') }
      .to change { workspace.credit_wallet.reload.available }.by(-Pricing.credits_for(kind: :video, seconds: 16))

    expect(generation.reload.params['voice_id']).to eq('voice_new')
    expect(creative.video_scenes.ordered.map(&:render_state)).to all(eq('stale'))
    expect(creative.video_scenes.first.voice_clip).not_to be_attached
    expect(creative.video_scenes.first.metadata).not_to have_key('voice_fingerprint')
    expect(Operations::Video::RenderScene).to have_received(:call).with(scene: creative.video_scenes.ordered.first)
  end

  it 'refuses an unknown voice' do
    expect { described_class.call(creative: creative, voice: 'Inexistente') }
      .to raise_error(Operations::Errors::Invalid, /não encontrada/)
  end
end
