# frozen_string_literal: true

require 'rails_helper'

# Per-network retry: re-arms ONE failed post and enqueues its publish job,
# without touching the ticket's other posts (no duplicate on the networks that
# already succeeded).
RSpec.describe Operations::Posts::Retry do
  let(:user) { User.create!(email: 'pretry@agencios.app', password: 'secret123', name: 'PR') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:ticket) do
    Operations::Tickets::Create.call(
      workspace: workspace, user: user, params: { project_id: project.id, title: 'T', channels: %w[instagram tiktok] }
    )
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    allow(Broadcaster).to receive(:ticket)
    allow(Broadcaster).to receive(:board)
    Current.workspace = workspace
  end

  after { Current.reset }

  def build_post(status, provider: 'instagram')
    account = client.social_accounts.find_by(provider: provider) ||
              client.social_accounts.create!(workspace: workspace, provider: provider)
    Post.create!(workspace: workspace, ticket: ticket, social_account: account,
                 status: status, scheduled_at: 1.hour.ago)
  end

  it 're-arms a failed post and enqueues ONLY its publish job' do
    failed = build_post(:failed)
    failed.update!(failure_reason: 'token expired')
    published = build_post(:published, provider: 'tiktok')

    expect { described_class.call(post: failed) }
      .to have_enqueued_job(PublishPostJob).with(failed.id).exactly(:once)

    failed.reload
    expect(failed).to be_status_scheduled
    expect(failed.failure_reason).to be_nil
    expect(failed.scheduled_at).to be_within(5.seconds).of(Time.current)
    expect(published.reload).to be_status_published
  end

  it 'refuses a post that has not failed' do
    %i[scheduled publishing published].each do |status|
      post = build_post(status, provider: 'instagram')

      expect { described_class.call(post: post) }
        .to raise_error(Operations::Errors::Invalid)

      post.destroy!
    end
  end
end
