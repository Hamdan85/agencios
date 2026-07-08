# frozen_string_literal: true

require 'rails_helper'

# Covers what happens when a workspace ends up with more active members than
# its plan allows: a preventive block on downgrading in-app
# (Controllers::Billing::ChangePlan), and a soft-lock safety net for a
# downgrade applied outside the app — e.g. the Stripe dashboard — reconciled
# via Operations::Billing::SyncSubscription. Neither path ever removes a
# member; they only gate further seat/work-creating actions.
RSpec.describe 'Seat compliance on plan downgrade' do
  before do
    ActiveJob::Base.queue_adapter = :test
    Pricing.seed_defaults!
  end

  after { Current.reset }

  def register_with_members(plan:, member_count:, stripe_subscription_id: nil)
    owner, workspace = Operations::Users::Register.call(
      email: "owner-#{SecureRandom.hex(4)}@agencios.app", password: 'secret123',
      name: 'Owner', workspace_name: 'Agency'
    )
    activate_billing(workspace)
    workspace.subscription.update!(plan: plan, seats: member_count, stripe_subscription_id: stripe_subscription_id)
    (member_count - 1).times do |i|
      user = User.create!(email: "member-#{SecureRandom.hex(4)}-#{i}@agencios.app", password: 'secret123',
                          name: "M#{i}")
      Membership.create!(workspace: workspace, user: user, role: :member)
    end
    Current.workspace = workspace
    Current.membership = workspace.memberships.find_by(user: owner)
    [owner, workspace]
  end

  describe 'Workspace#sync_seat_compliance!' do
    it "flags the workspace when members exceed the plan's seat limit" do
      _owner, workspace = register_with_members(plan: :solo, member_count: 3) # Solo = 2 seats
      workspace.sync_seat_compliance!
      expect(workspace.over_seat_limit?).to be(true)
    end

    it 'clears the flag once membership fits the limit again' do
      _owner, workspace = register_with_members(plan: :solo, member_count: 3)
      workspace.update!(over_seat_limit: true)
      workspace.subscription.update!(plan: :agencia) # Agência = 20 seats
      workspace.sync_seat_compliance!
      expect(workspace.over_seat_limit?).to be(false)
    end

    it 'never flags a godfathered workspace' do
      _owner, workspace = register_with_members(plan: :solo, member_count: 3)
      workspace.update!(godfathered: true)
      workspace.sync_seat_compliance!
      expect(workspace.over_seat_limit?).to be(false)
    end

    it 'ignores a STALE over_seat_limit flag once godfathered (no re-sync needed)' do
      _owner, workspace = register_with_members(plan: :solo, member_count: 3)
      # Flag set true while on a limited plan, THEN godfathered without a re-sync —
      # the exact state that surfaced the bug (banner + write-block on a founding ws).
      workspace.update!(over_seat_limit: true)
      workspace.update!(godfathered: true)
      expect(workspace.over_seat_limit?).to be(false)
      expect(workspace.seat_limit).to eq(Float::INFINITY)
    end
  end

  describe 'Controllers::Billing::ChangePlan' do
    it 'blocks a downgrade that would leave more members than the new plan allows' do
      _owner, workspace = register_with_members(plan: :agencia, member_count: 3, stripe_subscription_id: 'sub_1')

      expect do
        Controllers::Billing::ChangePlan.call(params: { plan: 'solo', interval: 'month' })
      end.to raise_error(Operations::Errors::SeatLimitReached, /3 membros/)

      expect(workspace.subscription.reload.plan).to eq('agencia') # untouched — no Stripe call made
    end

    it "allows a downgrade that fits the new plan's seat limit" do
      _owner, = register_with_members(plan: :agencia, member_count: 1, stripe_subscription_id: 'sub_1')
      allow(Vendors::Stripe::Actions::UpdateSubscription).to receive(:call)

      Controllers::Billing::ChangePlan.call(params: { plan: 'solo', interval: 'month' })

      expect(Vendors::Stripe::Actions::UpdateSubscription).to have_received(:call)
    end
  end

  describe 'Operations::Billing::SyncSubscription soft-lock' do
    def downgrade_event(workspace, price_id:, quantity:)
      { 'type' => 'customer.subscription.updated',
        'data' => { 'object' => {
          'id' => 'sub_1', 'customer' => 'cus_1', 'status' => 'active',
          'items' => { 'data' => [{ 'id' => 'si_1', 'quantity' => quantity,
                                    'price' => { 'id' => price_id, 'recurring' => { 'interval' => 'month' } } }] },
          'metadata' => { 'workspace_id' => workspace.id.to_s }
        } } }
    end

    before { PricingPlan.find_by(key: 'solo').update!(stripe_price_id: 'price_solo_m') }

    it 'flags the workspace when a Stripe-side downgrade outpaces the app' do
      _owner, workspace = register_with_members(plan: :agencia, member_count: 3, stripe_subscription_id: 'sub_1')

      Operations::Billing::SyncSubscription.call(
        downgrade_event(workspace, price_id: 'price_solo_m', quantity: 1), client: double('StripeClient')
      )

      expect(workspace.reload.over_seat_limit?).to be(true)
      expect(workspace.subscription.plan).to eq('solo')
    end

    it 'blocks new tickets and projects while flagged, without touching existing members' do
      _owner, workspace = register_with_members(plan: :agencia, member_count: 3, stripe_subscription_id: 'sub_1')
      Operations::Billing::SyncSubscription.call(
        downgrade_event(workspace, price_id: 'price_solo_m', quantity: 1), client: double('StripeClient')
      )
      workspace.reload # SyncSubscription resolves its own Workspace instance from the event
      expect(workspace.memberships.count).to eq(3) # nobody removed

      client = workspace.clients.create!(name: 'ACME')
      project = workspace.projects.create!(client: client, name: 'Launch', color: '#7C3AED')

      expect do
        Controllers::Tickets::Create.call(params: ActionController::Parameters.new(
          ticket: { project_id: project.id, title: 'Reel', creative_type: 'reel', channels: %w[instagram] }
        ))
      end.to raise_error(Operations::Errors::SeatLimitReached)

      expect do
        Controllers::Projects::Create.call(params: ActionController::Parameters.new(
          project: { client_id: client.id, name: 'Another', color: '#000000' }
        ))
      end.to raise_error(Operations::Errors::SeatLimitReached)
    end
  end
end
