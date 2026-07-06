# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PostDetailSerializer do
  it 'serializes metric history ascending + creative experience' do
    ws = Workspace.create!(name: 'WS', slug: "ws-#{SecureRandom.hex(4)}")
    client = Client.create!(workspace: ws, name: 'C')
    project = Project.create!(workspace: ws, client: client, name: 'P', status: :active)
    ticket = Ticket.create!(workspace: ws, project: project, status: :published)
    acct = SocialAccount.create!(workspace: ws, client: client, provider: :instagram)
    post = Post.create!(workspace: ws, ticket: ticket, social_account: acct, status: :published, published_at: Time.current)
    post.post_metrics.create!(captured_at: 2.days.ago, views: 10, likes: 1)
    post.post_metrics.create!(captured_at: 1.day.ago, views: 30, likes: 4)

    json = PostDetailSerializer.new(post).as_json
    expect(json[:metric_history].map { |m| m[:views] }).to eq([10, 30]) # ascending by captured_at
    expect(json[:client_name]).to eq('C')
    expect(json[:campaign_name]).to eq('P')
    expect(json[:provider]).to eq('instagram')
  end
end
