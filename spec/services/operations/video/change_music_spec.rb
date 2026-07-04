# frozen_string_literal: true

require 'rails_helper'

# Changing the background track re-mixes only (no scene re-render, no credits).
RSpec.describe Operations::Video::ChangeMusic do
  let(:user) { User.create!(email: 'mus@agencios.app', password: 'secret123', name: 'Mus') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:ticket) do
    Operations::Tickets::Create.call(workspace: workspace, user: user,
                                     params: { project_id: project.id, title: 'Reel', creative_type: 'ugc_video', channels: %w[instagram] })
  end
  let(:creative) do
    Operations::Creatives::Create.call(ticket: ticket, creative_type: 'ugc_video',
                                       source: :generated, status: :ready, provider: 'openrouter')
  end
  let(:generation) do
    workspace.generations.create!(user: user, creative: creative, kind: :video, status: :completed,
                                  provider: 'openrouter', params: { mode: 'avatar', with_audio: true, music_mood: 'calm' })
  end
  let(:scene) do
    Operations::Video::Scenes::Create.call(creative: creative, position: 0, mode: 'avatar',
                                           prompt: 'p0', duration_seconds: 8, aspect_ratio: '9:16')
                                     .tap do |s|
      s.clip.attach(io: StringIO.new('MP4'), filename: 's0.mp4', content_type: 'video/mp4')
      s.update!(render_state: :ready)
    end
  end

  before do
    Current.workspace = workspace
    Current.actor = user
    # Jamendo (the open base) returns a track for any search.
    allow(Vendors::Jamendo::Actions::SearchTracks).to receive(:call).and_return(
      { url: 'https://jamendo/upbeat.mp3', title: 'Upbeat One', attribution: 'Upbeat One — Artist' }
    )
    allow(Operations::Video::Compose).to receive(:call)
    generation && scene # force creation now that Current is set
  end

  after { Current.reset }

  it 'sets the new mood + track and re-mixes (no re-render), without charging credits' do
    expect do
      described_class.call(creative: creative, mood: 'upbeat')
    end.not_to change { workspace.credit_transactions.count }

    expect(generation.reload.params).to include('music_mood' => 'upbeat', 'music_url' => 'https://jamendo/upbeat.mp3')
    expect(Operations::Video::Compose).to have_received(:call).with(creative: creative, remix: true)
  end

  it 'removes the music on "none"' do
    described_class.call(creative: creative, mood: 'none')

    expect(generation.reload.params).not_to include('music_url')
    expect(generation.params).not_to include('music_mood')
    expect(Operations::Video::Compose).to have_received(:call).with(creative: creative, remix: true)
  end

  it 'refuses on a silent video' do
    generation.update!(params: generation.params.merge('with_audio' => false))
    expect { described_class.call(creative: creative, mood: 'upbeat') }
      .to raise_error(Operations::Errors::Invalid, /silencioso/)
  end
end
