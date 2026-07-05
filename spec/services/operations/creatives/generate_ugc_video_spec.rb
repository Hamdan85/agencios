# frozen_string_literal: true

require 'rails_helper'

# Video generation runs through OpenRouter as a SEQUENCE OF SCENES. The request
# half (GenerateUgcVideo) is FAST: it creates the creative + generation, holds
# the credit estimate and enqueues StartVideoRenderJob. The slow half
# (Operations::Video::StartRender) plans the storyboard, creates the scenes and
# submits the first render — the poll chain advances the rest. The vendor Action
# is stubbed so the spec stays offline.
RSpec.describe Operations::Creatives::GenerateUgcVideo do
  include ActiveJob::TestHelper

  let(:user) { User.create!(email: 'vid@agencios.app', password: 'secret123', name: 'Vid') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:ticket) do
    Operations::Tickets::Create.call(
      workspace: workspace, user: user,
      params: { project_id: project.id, title: 'Reel', creative_type: 'ugc_video', channels: %w[instagram tiktok] }
    )
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    Current.workspace = workspace
    Current.actor = user
    Operations::Credits::EnsureWallet.call(workspace: workspace).update!(purchased_balance: 10_000)
    allow(Vendors::OpenRouter::Actions::GenerateVideo).to receive(:call).and_return('job_abc123')
    # Force the deterministic storyboard fallback (no live AI in specs) so scene
    # counts are predictable — PlanScenes rescues the AI error to its beats.
    allow(Vendors::Ai).to receive(:client).and_raise(StandardError, 'no ai in test')
  end

  after { Current.reset }

  # Runs the async half inline (what StartVideoRenderJob does off-request).
  def run_start_render(generation)
    Operations::Video::StartRender.call(generation: generation)
  end

  it 'returns fast: creates the generating creative + processing generation, holds credits, enqueues the render job' do
    generation = nil
    expect do
      generation = described_class.call(ticket: ticket, mode: 'avatar',
                                        script: 'Primeira frase. Segunda frase.', duration: 16)
    end.to change(Generation, :count).by(1)

    expect(generation).to have_attributes(kind: 'video', status: 'processing', provider: 'openrouter')
    expect(generation.creative.status).to eq('generating')
    # NOTHING slow ran in-request: no scenes yet, no vendor submit.
    expect(generation.creative.video_scenes).to be_empty
    expect(Vendors::OpenRouter::Actions::GenerateVideo).not_to have_received(:call)
    expect(StartVideoRenderJob).to have_been_enqueued.with(generation.id)

    # Credits held up front for the requested duration.
    debit = workspace.credit_transactions.debits.where(generation_id: generation.id).last
    expect(-debit.amount).to eq(Pricing.credits_for(kind: :video, seconds: 16))
  end

  it 'StartRender plans the scenes and submits only the first (sequential continuity chain)' do
    generation = described_class.call(ticket: ticket, mode: 'avatar',
                                      script: 'Primeira frase. Segunda frase.', duration: 16)
    run_start_render(generation)

    scenes = generation.creative.video_scenes.ordered
    expect(scenes.size).to eq(2) # one per sentence
    expect(scenes.first).to have_attributes(render_state: 'rendering', external_id: 'job_abc123')
    expect(scenes.last).to have_attributes(render_state: 'fresh')
    expect(PollVideoSceneJob).to have_been_enqueued.once
  end

  it 'is idempotent — a retried StartRender does not duplicate scenes' do
    generation = described_class.call(ticket: ticket, mode: 'avatar', script: 'Oi. Tudo bem.', duration: 16)
    run_start_render(generation)

    expect { run_start_render(generation) }.not_to change { generation.creative.video_scenes.count }
  end

  it 'passes product reference photos into the product scene render' do
    generation = described_class.call(ticket: ticket, mode: 'product', prompt: 'Café gelado',
                                      reference_image_urls: ['https://cdn.example.com/cup.jpg', ' '], duration: 8)
    run_start_render(generation)

    expect(Vendors::OpenRouter::Actions::GenerateVideo).to have_received(:call).with(
      hash_including(mode: 'product', input_references: [{ url: 'https://cdn.example.com/cup.jpg', type: 'image_url' }])
    ).at_least(:once)
  end

  it 'clamps total duration to the configured maximum' do
    allow(VideoConfig).to receive(:instance).and_return(VideoConfig.new(max_duration_seconds: 20))
    gen = described_class.call(ticket: ticket, mode: 'avatar', script: 'oi', duration: 999)
    run_start_render(gen)
    expect(gen.creative.video_scenes.sum(&:duration_seconds)).to be <= 20
  end

  it 'refunds held credits and marks failed when the first scene submit errors' do
    allow(Vendors::OpenRouter::Actions::GenerateVideo).to receive(:call).and_raise(StandardError, 'boom')
    generation = described_class.call(ticket: ticket, mode: 'avatar', script: 'oi', duration: 16)

    expect { run_start_render(generation) }.to raise_error(StandardError, 'boom')

    expect(generation.reload.status).to eq('failed')
    expect(generation.failure_reason).to eq('boom')
    expect(generation.creative.status).to eq('failed')
    expect(workspace.credit_transactions.where(generation_id: generation.id).sum(:amount)).to eq(0)
  end
end
