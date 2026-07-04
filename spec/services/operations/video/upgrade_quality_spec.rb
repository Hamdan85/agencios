# frozen_string_literal: true

require 'rails_helper'

# Draft-first quality: a video renders on the fast/cheap model; approving it
# re-renders the whole storyboard (same prompts) on the final model, charged and
# sequential (continuity chain).
RSpec.describe Operations::Video::UpgradeQuality do
  include ActiveJob::TestHelper

  let(:user) { User.create!(email: 'up@agencios.app', password: 'secret123', name: 'Up') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:ticket) do
    Operations::Tickets::Create.call(
      workspace: workspace, user: user,
      params: { project_id: project.id, title: 'Reel', creative_type: 'ugc_video', channels: %w[instagram] }
    )
  end
  let(:creative) do
    Operations::Creatives::Create.call(ticket: ticket, creative_type: 'ugc_video',
                                       source: :generated, status: :ready, provider: 'openrouter',
                                       metadata: { 'quality' => 'draft' })
  end
  let(:generation) do
    workspace.generations.create!(user: user, creative: creative, kind: :video, status: :completed,
                                  provider: 'openrouter', params: { 'mode' => 'avatar', 'quality' => 'draft' })
  end
  let(:scenes) do
    Array.new(2) do |i|
      Operations::Video::Scenes::Create.call(creative: creative, position: i, mode: 'avatar',
                                             prompt: "p#{i}", duration_seconds: 8, aspect_ratio: '9:16')
                                       .tap do |s|
        s.clip.attach(io: StringIO.new('MP4'), filename: "s#{i}.mp4", content_type: 'video/mp4')
        s.update!(render_state: :ready)
      end
    end
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    Current.workspace = workspace
    Current.actor = user
    Operations::Credits::EnsureWallet.call(workspace: workspace).update!(purchased_balance: 10_000)
    allow(Vendors::OpenRouter::Actions::GenerateVideo).to receive(:call).and_return('job_final')
    generation
    scenes
  end

  after { Current.reset }

  it 'charges, flips quality to final, and restarts the sequential chain from scene 1' do
    described_class.call(creative: creative)

    expect(generation.reload.status).to eq('processing')
    expect(generation.params['quality']).to eq('final')
    expect(creative.reload.status).to eq('generating')
    expect(creative.metadata['quality']).to eq('final')

    # Only scene 1 submitted (continuity); scene 2 queued as stale.
    expect(scenes[0].reload.render_state).to eq('rendering')
    expect(scenes[1].reload.render_state).to eq('stale')
    expect(Vendors::OpenRouter::Actions::GenerateVideo).to have_received(:call).once

    debit = workspace.credit_transactions.debits.where(generation_id: generation.id).last
    expect(-debit.amount).to eq(Pricing.credits_for(kind: :video, seconds: 16))
  end

  it 'uses the FINAL model on the upgraded render' do
    VideoConfig.first_or_create!.update!(mode_models: { 'avatar' => 'google/veo-3.1' },
                                         draft_models: { 'avatar' => 'google/veo-3.1-fast' })

    described_class.call(creative: creative)

    expect(Vendors::OpenRouter::Actions::GenerateVideo).to have_received(:call).with(
      hash_including(model: 'google/veo-3.1')
    )
  end

  it 'refuses when already final or still busy' do
    generation.update!(params: generation.params.merge('quality' => 'final'))
    expect { described_class.call(creative: creative) }
      .to raise_error(Operations::Errors::Invalid, /alta qualidade/)

    generation.update!(params: generation.params.merge('quality' => 'draft'))
    scenes[0].update!(render_state: :rendering)
    expect { described_class.call(creative: creative) }
      .to raise_error(Operations::Errors::Invalid, /processamento/)
  end
end
