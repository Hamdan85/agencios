# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Workspace, type: :model do
  let(:workspace) { Workspace.create!(name: 'W', slug: "w-#{SecureRandom.hex(4)}") }

  describe 'godfathered bypass' do
    before { Subscription.create!(workspace: workspace, plan: :solo, seats: 1, status: 'canceled') }

    it 'grants access even with a canceled subscription' do
      expect(workspace.billing_active?).to be(false)
      workspace.update!(godfathered: true)
      expect(workspace.billing_active?).to be(true)
    end

    it 'has an unlimited seat and client limit' do
      workspace.update!(godfathered: true)
      expect(workspace.seat_limit).to eq(Float::INFINITY)
      expect(workspace.client_limit).to eq(Float::INFINITY)
      expect(workspace.within_seat_limit?).to be(true)
    end

    it 'reports credits_available as 0 (never debited)' do
      workspace.update!(godfathered: true)
      expect(workspace.credits_available).to eq(0)
    end
  end

  describe 'seat limit from plan' do
    it 'reads the Pricing seat limit for the plan' do
      Subscription.create!(workspace: workspace, plan: :solo, seats: 1, status: 'active')
      expect(workspace.seat_limit).to eq(Pricing.seat_limit_for(:solo))
    end
  end
end
