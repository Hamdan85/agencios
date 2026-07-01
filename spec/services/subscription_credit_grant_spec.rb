# frozen_string_literal: true

require "rails_helper"

# Guards the trial credit exploit: a trialing subscription must NOT receive the
# plan's monthly credits (otherwise a user could spend them and cancel before
# paying). Credits are granted only on a real (amount_paid > 0) invoice.
RSpec.describe Operations::Billing::SyncSubscription do
  let(:workspace) do
    ws = Workspace.create!(name: "W", slug: "w-#{SecureRandom.hex(4)}")
    Subscription.create!(workspace: ws, plan: :solo, status: "incomplete")
    ws
  end

  before do
    Pricing.seed_defaults!
    PricingPlan.find_by(key: "agencia").update!(stripe_price_id: "price_ag_m")
  end

  # A Stripe subscription object (Hash — the `read` helper handles Hashes).
  def stripe_sub(status:)
    {
      "id" => "sub_1", "customer" => "cus_1", "status" => status,
      "items" => { "data" => [{ "id" => "si_1",
                                "price" => { "id" => "price_ag_m", "recurring" => { "interval" => "month" } } }] },
      "trial_end" => (Time.current + 7.days).to_i,
      "metadata" => { "workspace_id" => workspace.id.to_s }
    }
  end

  def fake_client(sub) = Struct.new(:sub) { def retrieve_subscription(*) = sub }.new(sub)

  def checkout_event
    { "type" => "checkout.session.completed",
      "data" => { "object" => { "id" => "cs_1", "subscription" => "sub_1",
                                "metadata" => { "workspace_id" => workspace.id.to_s } } } }
  end

  def invoice_event(amount_paid:)
    { "type" => "invoice.paid",
      "data" => { "object" => { "subscription" => "sub_1", "amount_paid" => amount_paid } } }
  end

  it "does NOT grant credits when the checkout starts a trial" do
    described_class.call(checkout_event, client: fake_client(stripe_sub(status: "trialing")))

    sub = workspace.subscription.reload
    expect(sub.status).to eq("trialing")
    expect(sub.trial_used).to be(true)       # trial consumed (no repeat trial)
    expect(sub.card_on_file).to be(true)
    expect(workspace.reload.credits_available).to eq(0) # ← no free trial credits
  end

  it "grants the plan credits only once real money is paid" do
    described_class.call(checkout_event, client: fake_client(stripe_sub(status: "trialing")))
    expect(workspace.reload.credits_available).to eq(0)

    described_class.call(invoice_event(amount_paid: 34_900), client: fake_client(nil))
    expect(workspace.reload.credits_available).to eq(Pricing.included_credits_for("agencia")) # 200
  end

  it "does NOT grant on a R$0 invoice (trial invoice)" do
    described_class.call(checkout_event, client: fake_client(stripe_sub(status: "trialing")))
    described_class.call(invoice_event(amount_paid: 0), client: fake_client(nil))

    expect(workspace.reload.credits_available).to eq(0)
  end
end
