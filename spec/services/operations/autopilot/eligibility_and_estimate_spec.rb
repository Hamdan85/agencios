# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Operations::Autopilot eligibility + estimate' do
  let(:user) { User.create!(email: "go-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'Go') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'GO Studio') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }

  before do
    Current.workspace = workspace
    Current.actor = user
  end

  after { Current.reset }

  def ticket_with(types)
    t = Operations::Tickets::Create.call(
      workspace: workspace, user: user, params: { project_id: project.id, title: 'T' }
    )
    Operations::Tickets::UpdateFields.call(ticket: t, status: 'scoping', values: { 'creative_types' => types })
    t.reload
  end

  describe Operations::Autopilot::Eligibility do
    it 'is eligible when every scoped type is auto-generatable' do
      result = described_class.call(ticket: ticket_with(%w[carousel feed_image ugc_video]))
      expect(result[:eligible]).to be(true)
      expect(result[:blocking_types]).to be_empty
    end

    it 'is blocked by a non-generatable type (cover) and names it' do
      result = described_class.call(ticket: ticket_with(%w[carousel cover]))
      expect(result[:eligible]).to be(false)
      expect(result[:blocking_types]).to eq(%w[cover])
    end

    it 'is blocked when no creative types are scoped' do
      expect(described_class.call(ticket: ticket_with([]))[:eligible]).to be(false)
    end
  end

  describe Operations::Autopilot::Estimate do
    it 'sums credits with the same math the debit uses (video 16 + image 1 + carousel 0)' do
      ticket = ticket_with(%w[ugc_video feed_image carousel])
      Operations::Credits::Purchase.call(workspace: workspace, amount: 50, reference: 'seed')

      est = described_class.call(tickets: [ticket], workspace: workspace)

      expect(est[:total_credits]).to eq(17)
      expect(est[:eligible]).to be(true)
      expect(est[:shortfall]).to eq(0)
      expect(est[:tickets].first[:subtotal]).to eq(17)
    end

    it 'reports a shortfall and suggests a pack when the wallet is short' do
      ticket = ticket_with(%w[ugc_video]) # 16 credits, empty wallet
      est = described_class.call(tickets: [ticket], workspace: workspace)

      expect(est[:total_credits]).to eq(16)
      expect(est[:available]).to eq(0)
      expect(est[:shortfall]).to eq(16)
      expect(est[:packs_suggestion]).not_to be_empty
    end

    it 'treats an unlimited godfathered workspace as infinite (no shortfall, available nil)' do
      workspace.update!(godfathered: true, monthly_credit_limit: nil)
      ticket = ticket_with(%w[ugc_video]) # 16 credits, but wallet is empty / absent

      est = described_class.call(tickets: [ticket], workspace: workspace)

      expect(est[:total_credits]).to eq(16)
      expect(est[:unlimited]).to be(true)
      expect(est[:available]).to be_nil
      expect(est[:shortfall]).to eq(0)
      expect(est[:packs_suggestion]).to be_empty
    end

    it 'flags blocking tickets so a project GO can be refused' do
      good = ticket_with(%w[carousel])
      bad = ticket_with(%w[cover])
      est = described_class.call(tickets: [good, bad], workspace: workspace)

      expect(est[:eligible]).to be(false)
      expect(est[:blocking_tickets].map { |t| t[:ticket_id] }).to eq([bad.id])
    end
  end
end
