# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Controllers::Credits::Usage, type: :model do
  let(:workspace) { Workspace.create!(name: 'W', slug: "w-#{SecureRandom.hex(4)}") }

  before { Current.workspace = workspace }
  after  { Current.reset }

  def gen(kind, provider)
    workspace.generations.create!(kind: kind, status: :completed, provider: provider)
  end

  it 'splits activity counts from credit spend (carousel is free)' do
    Operations::Credits::Grant.call(workspace: workspace, amount: 100, expires_at: 1.month.from_now)

    video = gen(:video, 'heygen')
    Operations::Credits::Debit.call(workspace: workspace, amount: 16, generation: video)

    2.times do
      image = gen(:image, 'google_banana')
      Operations::Credits::Debit.call(workspace: workspace, amount: 1, generation: image)
    end

    carousel = gen(:carousel, 'internal')
    # Carousel is 0 credits — Debit is a no-op and records no transaction.
    Operations::Credits::Debit.call(workspace: workspace, amount: Pricing.credits_for(kind: :carousel), generation: carousel)

    result = described_class.call(params: { range: '30d' })

    expect(result[:totals][:spent]).to eq(18)         # 16 + 1 + 1
    expect(result[:totals][:generations]).to eq(4)
    expect(result[:totals][:granted_added]).to eq(100)

    by_kind = result[:by_kind].index_by { |k| k[:kind] }
    expect(by_kind['video']).to include(count: 1, credits: 16)
    expect(by_kind['image']).to include(count: 2, credits: 2)
    expect(by_kind['carousel']).to include(count: 1, credits: 0)

    expect(result[:recent].size).to eq(4)
    expect(result[:recent].sum { |g| g[:credits] }).to eq(18)
  end

  it 'excludes activity outside the selected range' do
    old = gen(:image, 'google_banana')
    old.update_column(:created_at, 100.days.ago)
    Operations::Credits::Grant.call(workspace: workspace, amount: 50, expires_at: 1.month.from_now)
    Operations::Credits::Debit.call(workspace: workspace, amount: 1, generation: old)
    workspace.credit_transactions.debits.update_all(created_at: 100.days.ago)

    result = described_class.call(params: { range: '30d' })

    expect(result[:totals][:generations]).to eq(0)
    expect(result[:totals][:spent]).to eq(0)
  end
end
