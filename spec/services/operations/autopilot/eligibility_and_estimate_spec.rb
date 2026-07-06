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
    it 'excludes video from the total (never auto-generated) and flags pending video' do
      ticket = ticket_with(%w[ugc_video feed_image carousel])
      total = Pricing.credits_for(kind: :image) + Pricing.credits_for(kind: :carousel)
      Operations::Credits::Purchase.call(workspace: workspace, amount: total, reference: 'seed')

      est = described_class.call(tickets: [ticket], workspace: workspace)

      expect(est[:total_credits]).to eq(total) # video contributes 0
      expect(est[:eligible]).to be(true)
      expect(est[:shortfall]).to eq(0)
      expect(est[:tickets].first[:subtotal]).to eq(total)
      expect(est[:has_pending_video]).to be(true)
      expect(est[:pending_video_types]).to include('ugc_video')
    end

    it 'has no pending video when nothing is a video type' do
      est = described_class.call(tickets: [ticket_with(%w[carousel feed_image])], workspace: workspace)
      expect(est[:has_pending_video]).to be(false)
      expect(est[:pending_video_types]).to be_empty
    end

    it 'reports a shortfall and suggests a pack when the wallet is short' do
      ticket = ticket_with(%w[feed_image]) # empty wallet; image is metered, carousel is 0
      image = Pricing.credits_for(kind: :image)
      est = described_class.call(tickets: [ticket], workspace: workspace)

      expect(est[:total_credits]).to eq(image)
      expect(est[:available]).to eq(0)
      expect(est[:shortfall]).to eq(image)
      expect(est[:packs_suggestion]).not_to be_empty
    end

    it 'treats an unlimited godfathered workspace as infinite (no shortfall, available nil)' do
      workspace.update!(godfathered: true, monthly_credit_limit: nil)
      ticket = ticket_with(%w[feed_image]) # wallet is empty / absent
      image = Pricing.credits_for(kind: :image)

      est = described_class.call(tickets: [ticket], workspace: workspace)

      expect(est[:total_credits]).to eq(image)
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
