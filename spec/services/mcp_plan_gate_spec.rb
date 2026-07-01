# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MCP connector plan gate" do
  def workspace_with_plan(plan, godfathered: false)
    ws = Workspace.create!(name: "W", slug: "w-#{SecureRandom.hex(4)}", godfathered: godfathered)
    Subscription.create!(workspace: ws, plan: plan, seats: 1, status: "active")
    ws
  end

  describe "Workspace#mcp_enabled?" do
    it "is false for Solo" do
      expect(workspace_with_plan(:solo).mcp_enabled?).to be(false)
    end

    it "is true for Agência and Enterprise" do
      expect(workspace_with_plan(:agencia).mcp_enabled?).to be(true)
      expect(workspace_with_plan(:enterprise).mcp_enabled?).to be(true)
    end

    it "is true for a godfathered Solo workspace" do
      expect(workspace_with_plan(:solo, godfathered: true).mcp_enabled?).to be(true)
    end
  end

  describe "Mcp::ToolContext.for" do
    let(:user) { User.create!(email: "u-#{SecureRandom.hex(3)}@x.com", password: "secret123") }

    it "blocks workspace-scoped tools on a Solo workspace" do
      ws = workspace_with_plan(:solo)
      Membership.create!(workspace: ws, user: user, role: :owner)

      expect {
        Mcp::ToolContext.for(user: user, workspace_ref: ws.slug) { :ran }
      }.to raise_error(Mcp::ToolContext::PlanRequired)
    end

    it "allows workspace-scoped tools on an Agência workspace" do
      ws = workspace_with_plan(:agencia)
      Membership.create!(workspace: ws, user: user, role: :owner)

      expect(Mcp::ToolContext.for(user: user, workspace_ref: ws.slug) { :ran }).to eq(:ran)
    end
  end
end
