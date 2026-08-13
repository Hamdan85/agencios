# frozen_string_literal: true

require 'rails_helper'

# A post routed to the Stories surface (Publishers::PostBundle sets
# media["story"]) publishes through the STORIES container — image or video —
# instead of the feed flow.
RSpec.describe Vendors::Meta::Actions::PublishPost do
  let(:user) { User.create!(email: "st-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'St') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Story Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:ticket) { Operations::Tickets::Create.call(workspace: workspace, user: user, params: { project_id: project.id, title: 'T' }) }
  let(:creative) { Operations::Creatives::Create.call(ticket: ticket, creative_type: 'story', source: :generated, status: :ready) }
  let(:account) { client.social_accounts.create!(workspace: workspace, provider: 'instagram', ig_user_id: '123') }
  let(:post) do
    Post.create!(workspace: workspace, ticket: ticket, social_account: account, status: :scheduled,
                 scheduled_at: Time.current, caption: 'oi',
                 media: { 'creative_id' => creative.id.to_s, 'story' => true })
  end

  before do
    Current.workspace = workspace
    Current.actor = user
    allow(Vendors::Meta::Actions::GetContainerStatus).to receive(:call).and_return({ 'status_code' => 'FINISHED' })
    allow(Vendors::Meta::Actions::PublishMedia).to receive(:call).and_return({ 'id' => 'story1' })
    allow(Vendors::Meta::Actions::CreateStoryContainer).to receive(:call).and_return({ 'id' => 'story_c' })
    allow(Vendors::Meta::Actions::CreateMediaContainer).to receive(:call).and_return({ 'id' => 'img_c' })
    allow(Vendors::Meta::Client).to receive(:new).and_return(instance_double(Vendors::Meta::Client, get: { 'permalink' => 'http://x' }))
  end

  after { Current.reset }

  it 'publishes an image story via a STORIES container' do
    allow_any_instance_of(described_class).to receive(:video_url).and_return(nil)
    allow_any_instance_of(described_class).to receive(:image_urls).and_return(['https://cdn/s.jpg'])

    result = described_class.call(post)

    expect(Vendors::Meta::Actions::CreateStoryContainer).to have_received(:call).with(
      hash_including(social_account: account, image_url: 'https://cdn/s.jpg')
    )
    expect(result[:external_post_id]).to eq('story1')
  end

  it 'publishes a video story via a STORIES container' do
    allow_any_instance_of(described_class).to receive(:video_url).and_return('https://cdn/v.mp4')

    described_class.call(post)

    expect(Vendors::Meta::Actions::CreateStoryContainer).to have_received(:call).with(
      hash_including(social_account: account, video_url: 'https://cdn/v.mp4')
    )
  end

  it 'publishes an unflagged image post through the feed flow, never as a story' do
    post.update!(media: { 'creative_id' => creative.id.to_s })
    allow_any_instance_of(described_class).to receive(:video_url).and_return(nil)
    allow_any_instance_of(described_class).to receive(:image_urls).and_return(['https://cdn/s.jpg'])

    described_class.call(post)

    expect(Vendors::Meta::Actions::CreateStoryContainer).not_to have_received(:call)
    expect(Vendors::Meta::Actions::CreateMediaContainer).to have_received(:call)
  end
end
