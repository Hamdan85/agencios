# frozen_string_literal: true

require "rails_helper"

RSpec.describe Vendors::Stripe::Actions::EnsureCustomer do
  let(:workspace) { Workspace.create!(name: "ACME", slug: "acme-#{SecureRandom.hex(4)}") }

  # Minimal fake Stripe client that records create_customer calls.
  let(:client) do
    Class.new do
      attr_reader :calls
      def initialize = @calls = []
      def create_customer(**kwargs)
        @calls << kwargs
        Struct.new(:id).new("cus_#{@calls.size}")
      end
    end.new
  end

  before do
    Subscription.create!(workspace: workspace, plan: :solo, seats: 1, status: "incomplete")
    Membership.create!(workspace: workspace, user: User.create!(email: "o@x.com", password: "secret123"), role: :owner)
  end

  it "creates a Stripe customer, stamps workspace_id, and caches it on the subscription" do
    id = described_class.call(workspace: workspace, client: client)

    expect(id).to eq("cus_1")
    expect(workspace.subscription.reload.stripe_customer_id).to eq("cus_1")
    expect(client.calls.first[:metadata]).to eq(workspace_id: workspace.id.to_s)
    expect(client.calls.first[:email]).to eq("o@x.com")
  end

  it "is idempotent — returns the stored id without creating another customer" do
    workspace.subscription.update!(stripe_customer_id: "cus_existing")
    id = described_class.call(workspace: workspace, client: client)

    expect(id).to eq("cus_existing")
    expect(client.calls).to be_empty
  end
end
