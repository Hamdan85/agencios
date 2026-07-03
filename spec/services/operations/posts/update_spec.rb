# frozen_string_literal: true

require 'rails_helper'

# The single per-post edit authority: not-live posts only, and rescheduling a
# failed post re-arms it as a retry.
RSpec.describe Operations::Posts::Update do
  let(:user) { User.create!(email: 'pupd@agencios.app', password: 'secret123', name: 'PU') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:ticket) do
    Operations::Tickets::Create.call(
      workspace: workspace, user: user, params: { project_id: project.id, title: 'T', channels: %w[instagram] }
    )
  end

  before do
    allow(Broadcaster).to receive(:ticket)
    allow(Broadcaster).to receive(:board)
    Current.workspace = workspace
  end

  after { Current.reset }

  def build_post(status, at: 1.day.from_now)
    account = client.social_accounts.find_by(provider: 'instagram') ||
              client.social_accounts.create!(workspace: workspace, provider: 'instagram')
    Post.create!(workspace: workspace, ticket: ticket, social_account: account,
                 status: status, scheduled_at: at)
  end

  it 'reschedules a scheduled post (the sweep will publish at the new time)' do
    post = build_post(:scheduled)
    new_time = 3.days.from_now.change(hour: 11)

    described_class.call(post: post, attributes: { scheduled_at: new_time })

    expect(post.reload.scheduled_at).to be_within(1.second).of(new_time)
    expect(post).to be_status_scheduled
  end

  it 'rescheduling a FAILED post re-arms it: back to scheduled, failure cleared' do
    post = build_post(:failed)
    post.update!(failure_reason: 'rate limited')
    new_time = 2.days.from_now.change(hour: 9)

    described_class.call(post: post, attributes: { scheduled_at: new_time })

    post.reload
    expect(post).to be_status_scheduled
    expect(post.failure_reason).to be_nil
    expect(post.scheduled_at).to be_within(1.second).of(new_time)
  end

  it 'edits the caption of a not-yet-live post without touching its status' do
    post = build_post(:failed)

    described_class.call(post: post, attributes: { caption: 'Nova legenda' })

    post.reload
    expect(post.caption).to eq('Nova legenda')
    expect(post).to be_status_failed # no new time → no retry re-arm
  end

  it 'refuses to edit a published post (its caption/time are history)' do
    post = build_post(:published)

    expect { described_class.call(post: post, attributes: { scheduled_at: 1.day.from_now }) }
      .to raise_error(Operations::Errors::Invalid)
  end
end
