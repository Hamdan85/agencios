# frozen_string_literal: true

require 'rails_helper'

# Video generations never auto-generate — not even in GO. They wait in production
# for manual generation. This covers KickGenerations skipping video and Complete
# not requesting approval when nothing was generated.
RSpec.describe 'Autopilot video exception' do
  let(:user) { User.create!(email: "go-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'Go') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'GO Studio') }
  let(:client) { workspace.clients.create!(name: 'ACME', email: 'c@acme.co') }
  let(:project) do
    workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED',
                               settings: { 'require_client_approval' => true })
  end

  before do
    Current.workspace = workspace
    Current.actor = user
    allow(Operations::Push::Notify).to receive(:call)
  end

  after { Current.reset }

  def run_for(types)
    ticket = Ticket.create!(workspace: workspace, project: project, status: :production, creative_types: types)
    AutopilotRun.create!(workspace: workspace, ticket: ticket, user: user, scope: 'ticket',
                         state: 'generating', progress: { 'generation_ids' => [], 'creative_ids' => [] })
  end

  describe Operations::Autopilot::KickGenerations do
    it 'generates non-video creatives but skips video (video waits in production)' do
      run = run_for(%w[carousel ugc_video])
      expect(Operations::Creatives::GenerateUgcVideo).not_to receive(:call)
      # Stub creative lives OFF the ticket so it doesn't trip the "already has a
      # creative" skip — the ticket starts with no creatives here.
      carousel = Creative.create!(workspace: workspace, creative_type: 'carousel', status: :ready)
      gen = Generation.create!(workspace: workspace, user: user, kind: 'carousel', status: 'completed', creative: carousel)
      allow(Operations::Creatives::GenerateViralCarousel).to receive(:call).and_return(gen)

      described_class.call(run: run)

      expect(Operations::Creatives::GenerateViralCarousel).to have_received(:call)
    end

    it 'skips a type that already has a (non-failed) creative — no regen, no re-charge' do
      run = run_for(%w[carousel feed_image])
      # The ticket already has a ready carousel and a still-generating image.
      Creative.create!(workspace: workspace, ticket: run.ticket, creative_type: 'carousel', status: :ready)
      Creative.create!(workspace: workspace, ticket: run.ticket, creative_type: 'feed_image', status: :generating)
      expect(Operations::Creatives::GenerateViralCarousel).not_to receive(:call)
      expect(Operations::Creatives::GenerateImage).not_to receive(:call)

      described_class.call(run: run)

      # Nothing NEW generated — and the run ends where GO always ends: in Produção.
      expect(run.reload.ticket.status).to eq('production')
    end

    it 'still regenerates a type whose only creative FAILED' do
      run = run_for(%w[feed_image])
      Creative.create!(workspace: workspace, ticket: run.ticket, creative_type: 'feed_image', status: :failed)
      image = Creative.create!(workspace: workspace, creative_type: 'feed_image', status: :ready)
      gen = Generation.create!(workspace: workspace, user: user, kind: 'image', status: 'completed', creative: image)
      allow(Operations::Creatives::GenerateImage).to receive(:call).and_return(gen)

      described_class.call(run: run)

      expect(Operations::Creatives::GenerateImage).to have_received(:call)
    end

    it 'a video-only ticket generates nothing and stops at production without requesting approval' do
      run = run_for(%w[ugc_video])
      expect(Operations::Creatives::GenerateUgcVideo).not_to receive(:call)
      expect(Operations::Approvals::RequestApproval).not_to receive(:call)

      described_class.call(run: run)

      expect(run.reload.ticket.status).to eq('production')
    end
  end
end
