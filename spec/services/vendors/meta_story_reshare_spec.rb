# frozen_string_literal: true

require 'rails_helper'

# The combined-post flow: after an Instagram Reel publishes, a post flagged
# `share_to_story` reshares the SAME video to the story — best-effort, so a story
# failure must not fail the feed post.
RSpec.describe Vendors::Meta::Actions::PublishPost do
  let(:user) { User.create!(email: "st-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'St') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Story Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:ticket) { Operations::Tickets::Create.call(workspace: workspace, user: user, params: { project_id: project.id, title: 'T' }) }
  let(:creative) { Operations::Creatives::Create.call(ticket: ticket, creative_type: 'reel', source: :generated, status: :ready) }
  let(:account) { client.social_accounts.create!(workspace: workspace, provider: 'instagram', ig_user_id: '123') }
  let(:post) do
    Post.create!(workspace: workspace, ticket: ticket, social_account: account, status: :scheduled,
                 scheduled_at: Time.current, caption: 'oi',
                 media: { 'creative_id' => creative.id.to_s, 'share_to_story' => true })
  end

  before do
    Current.workspace = workspace
    Current.actor = user
    allow_any_instance_of(described_class).to receive(:video_url).and_return('https://cdn/v.mp4')
    allow_any_instance_of(described_class).to receive(:cover_url).and_return(nil)
    allow(Vendors::Meta::Actions::CreateReelsContainer).to receive(:call).and_return({ 'id' => 'reel_c' })
    allow(Vendors::Meta::Actions::GetContainerStatus).to receive(:call).and_return({ 'status_code' => 'FINISHED' })
    allow(Vendors::Meta::Actions::PublishMedia).to receive(:call).and_return({ 'id' => 'media1' }, { 'id' => 'story1' })
    allow(Vendors::Meta::Actions::CreateStoryContainer).to receive(:call).and_return({ 'id' => 'story_c' })
    allow(Vendors::Meta::Client).to receive(:new).and_return(instance_double(Vendors::Meta::Client, get: { 'permalink' => 'http://x' }))
  end

  after { Current.reset }

  it 'reshares the published video to the story via a STORIES container' do
    result = described_class.call(post)

    expect(Vendors::Meta::Actions::CreateStoryContainer).to have_received(:call).with(
      hash_including(social_account: account, video_url: 'https://cdn/v.mp4')
    )
    expect(result[:external_post_id]).to eq('media1')
    expect(post.reload.media['story_external_id']).to eq('story1')
  end

  it 'keeps the feed post successful when the story reshare fails' do
    allow(Vendors::Meta::Actions::CreateStoryContainer).to receive(:call).and_raise(Vendors::Base::Error, 'boom')

    result = described_class.call(post)

    expect(result[:external_post_id]).to eq('media1')
  end

  it 'does not reshare when the post is not flagged' do
    post.update!(media: { 'creative_id' => creative.id.to_s })

    described_class.call(post)

    expect(Vendors::Meta::Actions::CreateStoryContainer).not_to have_received(:call)
  end
end
