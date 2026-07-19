# frozen_string_literal: true

require 'rails_helper'

# Facebook analytics come from two independent calls: engagement off the stable
# post object, reach/views off the churn-prone /insights edge. The regression this
# guards: an insights failure used to unwind the whole method, throwing away the
# engagement numbers already in hand and persisting zeros for every FB post.
RSpec.describe Vendors::Meta::Actions::SyncInsights do
  let(:user) { User.create!(email: "si-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'Si') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Insights Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:ticket) { Operations::Tickets::Create.call(workspace: workspace, user: user, params: { project_id: project.id, title: 'T' }) }
  let(:account) do
    client.social_accounts.create!(workspace: workspace, provider: 'facebook',
                                  connection_type: 'facebook_login', page_access_token: 'tok')
  end
  let(:post) do
    Post.create!(workspace: workspace, ticket: ticket, social_account: account, status: :published,
                 scheduled_at: 1.day.ago, published_at: 1.day.ago, caption: 'oi',
                 external_post_id: '1163051450228350_122120888799355300')
  end

  let(:engagement_body) do
    {
      'reactions' => { 'summary' => { 'total_count' => 12 } },
      'comments' => { 'summary' => { 'total_count' => 3 } },
      'shares' => { 'count' => 5 }
    }
  end

  before do
    Current.workspace = workspace
    Current.actor = user
  end

  after { Current.reset }

  def metric_error
    Vendors::Base::Error.new('(#100) The value must be a valid insights metric', status: 400,
                                                                                body: { 'error' => { 'code' => 100 } })
  end

  it 'keeps likes/comments/shares when the insights edge is dead' do
    allow(Vendors::Meta::Actions::GetPostEngagement).to receive(:call).and_return(engagement_body)
    allow(Vendors::Meta::Actions::GetPostInsights).to receive(:call).and_raise(metric_error)

    result = described_class.call(post)

    expect(result).to include(likes: 12, comments: 3, shares: 5)
    # Reach/views are simply unknown — not a reason to discard engagement.
    expect(result).to include(reach: 0, views: 0)
  end

  it 'reads reach/views from whichever metric name survived' do
    allow(Vendors::Meta::Actions::GetPostEngagement).to receive(:call).and_return(engagement_body)
    allow(Vendors::Meta::Actions::GetPostInsights).to receive(:call).and_return(
      { 'data' => [{ 'name' => 'post_views', 'values' => [{ 'value' => 900 }] },
                   { 'name' => 'post_impressions_unique', 'values' => [{ 'value' => 700 }] }] }
    )

    expect(described_class.call(post)).to include(reach: 700, views: 900)
  end

  it 'raises when BOTH halves fail, so the caller writes no snapshot at all' do
    allow(Vendors::Meta::Actions::GetPostEngagement).to receive(:call).and_raise(metric_error)
    allow(Vendors::Meta::Actions::GetPostInsights).to receive(:call).and_raise(metric_error)

    expect { described_class.call(post) }.to raise_error(Vendors::Base::Error)
  end

  it 'never swallows a finished token — that is an account-level problem' do
    allow(Vendors::Meta::Actions::GetPostEngagement)
      .to receive(:call).and_raise(Vendors::Base::AuthenticationError.new('Invalid OAuth access token'))
    allow(Vendors::Meta::Actions::GetPostInsights).to receive(:call).and_return({ 'data' => [] })

    expect { described_class.call(post) }.to raise_error(Vendors::Base::AuthenticationError)
  end

  it 'returns nil when there is no external post to read' do
    post.update!(external_post_id: nil)

    expect(described_class.call(post)).to be_nil
  end
end
