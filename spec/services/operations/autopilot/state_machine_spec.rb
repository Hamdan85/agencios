# frozen_string_literal: true

require 'rails_helper'

# Drives the autopilot state machine directly (phase by phase), stubbing the
# heavy generation ops + AI carry-over so no external service is hit.
RSpec.describe 'Operations::Autopilot state machine' do
  include ActiveJob::TestHelper

  let(:user) { User.create!(email: "sm-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'SM') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'SM Studio') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }

  before do
    ActiveJob::Base.queue_adapter = :test
    Current.workspace = workspace
    Current.actor = user
    allow(Broadcaster).to receive(:ticket)
    allow(Broadcaster).to receive(:board)
    allow(Operations::Push::Notify).to receive(:call)
    # Autopilot fills fields via the real CarryOver → stub it to avoid the AI call.
    allow(Operations::Tickets::CarryOver).to receive(:call)
    # media_kind without ActiveStorage fixtures.
    allow_any_instance_of(Creative).to receive(:media_kind) do |c|
      %w[ugc_video reel].include?(c.creative_type) ? 'video' : (c.creative_type == 'carousel' ? 'carousel' : 'image')
    end
    stub_generation_ops
  end

  after { Current.reset }

  # Each generate op just creates the Creative + Generation autopilot expects.
  def stub_generation_ops
    allow(Operations::Creatives::GenerateImage).to receive(:call) do |ticket:, creative_type: nil, **|
      make_gen(ticket, :image, creative_type || 'feed_image', :completed)
    end
    allow(Operations::Creatives::GenerateViralCarousel).to receive(:call) do |ticket:, **|
      make_gen(ticket, :carousel, 'carousel', :completed)
    end
    allow(Operations::Creatives::GenerateUgcVideo).to receive(:call) do |ticket:, creative_type: nil, **|
      make_gen(ticket, :video, creative_type || 'ugc_video', :processing)
    end
  end

  def make_gen(ticket, kind, type, gen_status)
    creative = Operations::Creatives::Create.call(
      ticket: ticket, creative_type: type, source: :generated,
      status: gen_status == :completed ? :ready : :generating
    )
    workspace.generations.create!(user: user, creative: creative, kind: kind, status: gen_status, provider: 'test')
  end

  def eligible_ticket(types, channels)
    t = Operations::Tickets::Create.call(
      workspace: workspace, user: user, params: { project_id: project.id, title: 'T', channels: channels }
    )
    Operations::Tickets::UpdateFields.call(ticket: t, status: 'scoping',
                                           values: { 'creative_types' => types, 'channels' => channels })
    t.update!(scheduled_at: 2.days.from_now)
    t.reload
  end

  def connect(*providers)
    providers.each { |p| client.social_accounts.create!(workspace: workspace, provider: p) }
  end

  def advance(run) = Operations::Autopilot::Advance.call(run: run.reload)

  it 'walks a sync-only ticket straight through to completed with scheduled posts' do
    connect('instagram')
    ticket = eligible_ticket(%w[feed_image carousel], %w[instagram])
    run = Operations::Autopilot::Start.call(ticket: ticket, user: user)

    advance(run) # pending → generating (ticket now in production)
    expect(ticket.reload.status).to eq('production')

    advance(run) # generating → publishing (both creatives are sync)
    expect(run.reload.state).to eq('publishing')

    advance(run) # publishing → completed
    expect(run.reload.state).to eq('completed')
    expect(ticket.reload.status).to eq('scheduled')
    expect(ticket.posts.count).to be >= 1
  end

  it 'parks on an async video then resumes when the render settles' do
    connect('instagram')
    ticket = eligible_ticket(%w[ugc_video], %w[instagram])
    run = Operations::Autopilot::Start.call(ticket: ticket, user: user)

    advance(run) # → generating
    advance(run) # → awaiting_generation (video still processing)
    expect(run.reload.state).to eq('awaiting_generation')

    # Simulate the render finishing.
    gen = Generation.find(run.generation_ids.first)
    gen.update!(status: :completed)
    gen.creative.update!(status: :ready)
    Operations::Autopilot::OnGenerationSettled.reconcile(run: run.reload)
    expect(run.reload.state).to eq('publishing')

    advance(run)
    expect(run.reload.state).to eq('completed')
  end

  it 'halts the run when a generation fails' do
    connect('instagram')
    ticket = eligible_ticket(%w[ugc_video], %w[instagram])
    run = Operations::Autopilot::Start.call(ticket: ticket, user: user)
    advance(run)
    advance(run) # awaiting_generation

    Generation.find(run.generation_ids.first).update!(status: :failed)
    Operations::Autopilot::OnGenerationSettled.reconcile(run: run.reload)

    expect(run.reload.state).to eq('failed')
    expect(ticket.reload.status).to eq('production') # not scheduled
  end

  it 'is idempotent — a duplicate advance does not re-generate or double-advance' do
    connect('instagram')
    ticket = eligible_ticket(%w[feed_image], %w[instagram])
    run = Operations::Autopilot::Start.call(ticket: ticket, user: user)

    advance(run) # → generating
    advance(run) # → publishing (1 image generated)
    expect(Operations::Creatives::GenerateImage).to have_received(:call).once

    advance(run.reload) # duplicate generating tick would re-kick — but state moved on
    expect(Operations::Creatives::GenerateImage).to have_received(:call).once
  end
end
