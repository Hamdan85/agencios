# frozen_string_literal: true

require 'rails_helper'

# GO-mode: a client's change request on a NON-VIDEO creative starts a new
# generation that considers the feedback, superseding the old creative and
# re-requesting approval. A credit shortfall alerts the workspace admins instead.
RSpec.describe 'GO regeneration on client feedback' do
  include ActiveJob::TestHelper

  before { ActiveJob::Base.queue_adapter = :test }

  let(:owner) { User.create!(email: "own-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'Own') }
  let(:ws) { Operations::Workspaces::SetupForUser.call(user: owner, name: 'Studio') }
  let(:client) { ws.clients.create!(name: 'ACME', email: 'c@acme.co') }
  let(:project) { ws.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:ticket) { Ticket.create!(workspace: ws, project: project, status: :production, creative_types: ['carousel']) }
  let(:run) { AutopilotRun.create!(workspace: ws, ticket: ticket, user: owner, scope: 'ticket', state: 'completed', progress: {}) }
  let(:creative) do
    Creative.create!(workspace: ws, ticket: ticket, creative_type: 'carousel', status: :ready,
                     approval_state: 'changes_requested', client_feedback: 'Deixar mais colorido', version: 1)
  end

  before { Current.workspace = ws }
  after { Current.reset }

  describe Operations::Credits::NotifyAdmins do
    it 'emails and pushes the workspace owner/admins' do
      admin = User.create!(email: 'admin@a.co', password: 'secret123', name: 'Adm')
      ws.memberships.create!(user: admin, role: :admin)
      allow(Operations::Push::Notify).to receive(:call)

      perform_enqueued_jobs do
        described_class.call(workspace: ws, required: 50, context: 'Regeração para ACME')
      end

      recipients = ActionMailer::Base.deliveries.flat_map(&:to)
      expect(recipients).to include(owner.email, 'admin@a.co')
    end
  end

  describe Operations::Autopilot::Regenerate do
    it 'aborts and alerts admins when credits are insufficient (no generation)' do
      # feed_image is metered (carousel costs 0, so can never be unaffordable); empty wallet.
      image = Creative.create!(workspace: ws, ticket: ticket, creative_type: 'feed_image', status: :ready,
                               approval_state: 'changes_requested', client_feedback: 'x', version: 1)
      expect(Operations::Creatives::GenerateImage).not_to receive(:call)
      expect(Operations::Credits::NotifyAdmins).to receive(:call).with(hash_including(workspace: ws))

      described_class.call(run: run, creative: image, feedback: 'Mais claro')
      expect(image.reload.approval_state).to eq('changes_requested') # untouched
    end

    it 'regenerates with the feedback, supersedes the old creative, and re-requests approval' do
      Operations::Credits::Purchase.call(workspace: ws, amount: 100, reference: 'seed')
      new_creative = nil
      allow(Operations::Creatives::GenerateViralCarousel).to receive(:call) do |ticket:, params:|
        expect(params[:revision_notes]).to eq('Deixar mais colorido')
        new_creative = Creative.create!(workspace: ws, ticket: ticket, creative_type: 'carousel', status: :ready)
        ws.generations.create!(user: owner, creative: new_creative, kind: 'carousel', status: 'completed', provider: 'test')
      end
      expect(Operations::Approvals::RequestApproval).to receive(:call).with(hash_including(ticket: ticket))

      described_class.call(run: run, creative: creative, feedback: 'Deixar mais colorido')

      expect(new_creative.reload.parent_id).to eq(creative.id)
      expect(new_creative.version).to eq(2)
    end
  end
end
