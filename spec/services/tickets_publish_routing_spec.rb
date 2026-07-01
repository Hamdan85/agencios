# frozen_string_literal: true

require 'rails_helper'

# The posting step now publishes a BUNDLE of creatives (one per scoped type). For
# each channel, Operations::Tickets::Publish must send only the media the network
# supports, pair a cover/thumbnail image onto the video where supported, and skip
# the rest. This spec pins that routing without touching any real network.
RSpec.describe Operations::Tickets::Publish do
  include ActiveJob::TestHelper

  let(:user) { User.create!(email: 'pub@agencios.app', password: 'secret123', name: 'Pub') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }

  # media_kind is normally derived from the attached blobs; here we stub it by
  # creative_type so the spec needs no ActiveStorage fixtures.
  before do
    ActiveJob::Base.queue_adapter = :test
    Current.workspace = workspace
    Current.actor = user
    allow(Broadcaster).to receive(:ticket)
    allow_any_instance_of(Creative).to receive(:media_kind) do |c|
      case c.creative_type
      when 'reel', 'ugc_video' then 'video'
      when 'carousel' then 'carousel'
      else 'image'
      end
    end
  end

  after { Current.reset }

  def ticket_on(channels)
    Operations::Tickets::Create.call(
      workspace: workspace, user: user,
      params: { project_id: project.id, title: 'T', channels: channels }
    ).tap { |t| Operations::Tickets::ChangeStatus.call(t, 'scheduled', user: user, force: true) }
  end

  def creative(ticket, type)
    Operations::Creatives::Create.call(ticket: ticket, creative_type: type, source: :uploaded, status: :ready)
  end

  def connect(*providers)
    providers.each { |p| client.social_accounts.create!(workspace: workspace, provider: p) }
  end

  it 'pairs a thumbnail image onto the video as its cover on thumbnail-capable networks' do
    connect('youtube', 'instagram')
    ticket = ticket_on(%w[youtube instagram])
    reel = creative(ticket, 'reel')
    thumb = creative(ticket, 'thumbnail')

    result = described_class.call(ticket: ticket, user: user, creative_ids: [reel.id, thumb.id])

    posts = Post.where(id: result[:posts]).to_a
    expect(posts.size).to eq(2) # one video post per channel; the thumbnail rides as cover
    posts.each do |post|
      expect(post.media['creative_id']).to eq(reel.id.to_s)
      expect(post.media['cover_creative_id']).to eq(thumb.id.to_s)
    end
  end

  it "posts the cover image standalone on a network that can't attach a thumbnail" do
    connect('facebook')
    ticket = ticket_on(%w[facebook])
    reel = creative(ticket, 'reel')
    thumb = creative(ticket, 'thumbnail')

    result = described_class.call(ticket: ticket, user: user, creative_ids: [reel.id, thumb.id])

    media = Post.where(id: result[:posts]).map(&:media)
    expect(media).to contain_exactly(
      { 'creative_id' => reel.id.to_s },      # video post, no cover pairing on FB
      { 'creative_id' => thumb.id.to_s }      # cover falls back to a standalone image post
    )
  end

  it 'skips channels that support none of the selected media' do
    connect('tiktok')
    ticket = ticket_on(%w[tiktok])
    carousel = creative(ticket, 'carousel')

    expect do
      described_class.call(ticket: ticket, user: user, creative_ids: [carousel.id])
    end.to raise_error(Operations::Errors::Invalid, /Nenhum canal/)
  end

  it 'persists the selected creative_ids on the scheduled field bag' do
    connect('instagram')
    ticket = ticket_on(%w[instagram])
    img = creative(ticket, 'feed_image')

    described_class.call(ticket: ticket, user: user, creative_ids: [img.id])

    expect(ticket.reload.fields_for('scheduled')['creative_ids']).to eq([img.id.to_s])
  end
end
