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

    expect(result[:recent][:items].size).to eq(4)
    expect(result[:recent][:items].sum { |g| g[:credits] }).to eq(18)
    expect(result[:recent][:meta]).to include(total: 4)

    # The trend is zero-filled across the whole range (a continuous axis, never a
    # blank card) and carries both real spend and generation activity per bucket.
    expect(result[:series].size).to eq(31) # 30 days ago through today, inclusive
    expect(result[:series].sum { |p| p[:credits] }).to eq(18)
    expect(result[:series].sum { |p| p[:generations] }).to eq(4)
    today = result[:series].last
    expect(today[:credits]).to eq(18)
    expect(today[:generations]).to eq(4)

    # Each bucket breaks the spend/activity down per creative type so the trend
    # can draw one line per type; the parts always sum back to the bucket total.
    expect(today[:by_kind]['video']).to eq(credits: 16, generations: 1)
    expect(today[:by_kind]['image']).to eq(credits: 2, generations: 2)
    expect(today[:by_kind]['carousel']).to eq(credits: 0, generations: 1)
    expect(result[:series].sum { |p| p[:by_kind].values.sum { |v| v[:credits] } }).to eq(18)
    expect(result[:series].sum { |p| p[:by_kind].values.sum { |v| v[:generations] } }).to eq(4)
  end

  it 'filters and paginates the recent generations log' do
    Operations::Credits::Grant.call(workspace: workspace, amount: 100, expires_at: 1.month.from_now)
    images = Array.new(3) do
      img = gen(:image, 'google_banana')
      Operations::Credits::Debit.call(workspace: workspace, amount: 1, generation: img)
      img
    end
    2.times { gen(:carousel, 'internal') }
    images.first.update!(status: :failed)

    kind = described_class.call(params: { range: '30d', kind: 'image' })
    expect(kind[:recent][:items].map { |g| g[:kind] }.uniq).to eq(['image'])
    expect(kind[:recent][:meta][:total]).to eq(3)

    failed = described_class.call(params: { range: '30d', status: 'failed' })
    expect(failed[:recent][:items].map { |g| g[:status] }.uniq).to eq(['failed'])
    expect(failed[:recent][:meta][:total]).to eq(1)

    page1 = described_class.call(params: { range: '30d', per: 2, page: 1 })
    expect(page1[:recent][:items].size).to eq(2)
    expect(page1[:recent][:meta]).to include(total: 5, has_more: true)
    page3 = described_class.call(params: { range: '30d', per: 2, page: 3 })
    expect(page3[:recent][:items].size).to eq(1)
    expect(page3[:recent][:meta]).to include(has_more: false)
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
