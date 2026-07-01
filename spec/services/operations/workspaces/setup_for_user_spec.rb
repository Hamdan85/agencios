# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Workspaces::SetupForUser do
  let(:user) do
    User.create!(email: "owner-#{SecureRandom.hex(4)}@example.com", password: 'secret123', name: 'Owner')
  end

  it 'provisions the workspace Stripe customer immediately' do
    allow(Vendors::Stripe::Actions::EnsureCustomer).to receive(:call) do |workspace:|
      workspace.subscription.update!(stripe_customer_id: 'cus_new')
    end

    workspace = described_class.call(user: user, name: 'ACME')

    expect(Vendors::Stripe::Actions::EnsureCustomer).to have_received(:call).with(workspace: workspace)
    expect(workspace.subscription.reload.stripe_customer_id).to eq('cus_new')
  end

  it 'still creates the workspace when Stripe provisioning fails (lazy fallback at checkout)' do
    allow(Vendors::Stripe::Actions::EnsureCustomer)
      .to receive(:call).and_raise(Vendors::Base::NotConfiguredError.new('missing stripe.secret_key'))

    workspace = nil
    expect { workspace = described_class.call(user: user, name: 'ACME') }.not_to raise_error

    expect(workspace).to be_persisted
    expect(workspace.subscription).to be_present
    expect(workspace.subscription.stripe_customer_id).to be_nil
  end
end
