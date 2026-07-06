# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Analytics::PostsOverview do
  it 'aggregates published-post metrics by network and type' do
    ws = Workspace.create!(name: 'WS', slug: "ws-#{SecureRandom.hex(4)}")
    client = Client.create!(workspace: ws, name: 'C')
    project = Project.create!(workspace: ws, client: client, name: 'P', status: :active)
    ticket = Ticket.create!(workspace: ws, project: project, status: :published, creative_type: 'reel')
    ig = SocialAccount.create!(workspace: ws, client: client, provider: :instagram)
    post = Post.create!(workspace: ws, ticket: ticket, social_account: ig, status: :published, published_at: 2.days.ago)
    post.post_metrics.create!(captured_at: 1.day.ago, views: 100, likes: 10, comments: 2)

    out = described_class.call(workspace: ws, filters: { from: 7.days.ago.to_date.iso8601, to: Date.current.iso8601 })
    expect(out[:kpis][:views]).to eq(100)
    expect(out[:kpis][:engagement]).to eq(12)
    expect(out[:kpis][:posts_count]).to eq(1)
    expect(out[:by_network].first[:provider]).to eq('instagram')
    expect(out[:by_type].first[:creative_type]).to eq('reel')
  end
end
