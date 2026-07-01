# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Operations::Credits', type: :model do
  let(:workspace) { Workspace.create!(name: 'W', slug: "w-#{SecureRandom.hex(4)}") }

  def balance = Operations::Credits::EnsureWallet.call(workspace: workspace).reload.available

  describe 'Pricing.credits_for' do
    it 'charges 1 credit per image and 0 for carousel' do
      expect(Pricing.credits_for(kind: :image)).to eq(1)
      expect(Pricing.credits_for(kind: :carousel)).to eq(0)
    end

    it 'charges standard vs photoreal video per second' do
      expect(Pricing.credits_for(kind: :video, seconds: 30)).to eq(16)                       # 8/15 * 30
      expect(Pricing.credits_for(kind: :video, seconds: 30, engine: 'avatar_iv')).to eq(60)  # 2 * 30
    end
  end

  describe 'Grant + Purchase + Debit ordering' do
    it 'spends granted credits before purchased' do
      Operations::Credits::Grant.call(workspace: workspace, amount: 10, expires_at: 1.month.from_now)
      Operations::Credits::Purchase.call(workspace: workspace, amount: 5, reference: 'p1')
      expect(balance).to eq(15)

      Operations::Credits::Debit.call(workspace: workspace, amount: 12)
      wallet = workspace.credit_wallet.reload
      expect(wallet.granted_balance).to eq(0)      # 10 granted fully spent first
      expect(wallet.purchased_balance).to eq(3)    # then 2 from purchased
      expect(balance).to eq(3)
    end

    it 'raises InsufficientCredits and leaves the balance untouched' do
      Operations::Credits::Purchase.call(workspace: workspace, amount: 2, reference: 'p2')
      expect do
        Operations::Credits::Debit.call(workspace: workspace, amount: 5)
      end.to raise_error(Operations::Errors::InsufficientCredits)
      expect(balance).to eq(2)
    end
  end

  describe 'Grant resets and expires the previous allotment' do
    it 'replaces granted credits (use-it-or-lose-it)' do
      Operations::Credits::Grant.call(workspace: workspace, amount: 10, expires_at: 1.month.from_now)
      Operations::Credits::Debit.call(workspace: workspace, amount: 4)
      Operations::Credits::Grant.call(workspace: workspace, amount: 8, expires_at: 1.month.from_now)
      expect(workspace.credit_wallet.reload.granted_balance).to eq(8) # not 6+8
    end
  end

  describe 'Purchase idempotency' do
    it 'does not double-credit the same reference' do
      Operations::Credits::Purchase.call(workspace: workspace, amount: 50, reference: 'dup')
      Operations::Credits::Purchase.call(workspace: workspace, amount: 50, reference: 'dup')
      expect(balance).to eq(50)
    end
  end

  describe 'Refund' do
    it 'returns the exact per-bucket amounts a generation debit took' do
      Operations::Credits::Grant.call(workspace: workspace, amount: 10, expires_at: 1.month.from_now)
      Operations::Credits::Purchase.call(workspace: workspace, amount: 5, reference: 'r1')
      gen = workspace.generations.create!(kind: :video, status: :processing, provider: 'heygen')
      Operations::Credits::Debit.call(workspace: workspace, amount: 12, generation: gen)
      expect(balance).to eq(3)

      Operations::Credits::Refund.call(generation: gen)
      wallet = workspace.credit_wallet.reload
      expect(wallet.granted_balance).to eq(10)
      expect(wallet.purchased_balance).to eq(5)
    end

    it 'is idempotent' do
      Operations::Credits::Purchase.call(workspace: workspace, amount: 10, reference: 'r2')
      gen = workspace.generations.create!(kind: :image, status: :processing, provider: 'google_banana')
      Operations::Credits::Debit.call(workspace: workspace, amount: 1, generation: gen)
      2.times { Operations::Credits::Refund.call(generation: gen) }
      expect(balance).to eq(10)
    end
  end

  describe 'Godfathered workspaces never debit' do
    it 'is a no-op debit' do
      workspace.update!(godfathered: true)
      expect(Operations::Credits::Debit.call(workspace: workspace, amount: 999)).to eq(:godfathered)
    end
  end

  describe 'Godfathered workspaces with a monthly credit cap' do
    before { workspace.update!(godfathered: true, monthly_credit_limit: 20) }

    it 'grants the monthly allotment on first debit and spends from it' do
      Operations::Credits::Debit.call(workspace: workspace, amount: 5)
      wallet = workspace.credit_wallet.reload
      expect(wallet.granted_balance).to eq(15)          # 20 refilled, 5 spent
      expect(wallet.granted_expires_at).to be_present
      expect(workspace.credits_available).to eq(15)
    end

    it 'blocks a debit that exceeds the remaining monthly allotment' do
      Operations::Credits::Debit.call(workspace: workspace, amount: 18)
      expect do
        Operations::Credits::Debit.call(workspace: workspace, amount: 5)
      end.to raise_error(Operations::Errors::InsufficientCredits)
      expect(workspace.credits_available).to eq(2)
    end

    it 'reports the full cap before any allotment has been granted' do
      expect(workspace.credits_available).to eq(20)
    end

    it 'refunds a failed generation back into the allotment' do
      gen = workspace.generations.create!(kind: :image, status: :processing, provider: 'google_banana')
      Operations::Credits::Debit.call(workspace: workspace, amount: 3, generation: gen)
      expect(workspace.credits_available).to eq(17)
      Operations::Credits::Refund.call(generation: gen)
      expect(workspace.credit_wallet.reload.available).to eq(20)
    end

    it 'refills the allotment when the previous cycle has expired' do
      Operations::Credits::Debit.call(workspace: workspace, amount: 12)
      workspace.credit_wallet.update!(granted_expires_at: 1.day.ago)  # simulate cycle rollover

      Operations::Credits::Debit.call(workspace: workspace, amount: 4)
      wallet = workspace.credit_wallet.reload
      expect(wallet.granted_balance).to eq(16)          # refilled to 20, then 4 spent
    end

    it 'is idempotent within a cycle (does not top back up mid-month)' do
      Operations::Credits::Debit.call(workspace: workspace, amount: 8)
      Operations::Credits::EnsureGodfatheredGrant.call(workspace: workspace)
      expect(workspace.credit_wallet.reload.granted_balance).to eq(12) # still 12, not re-granted to 20
    end
  end
end
