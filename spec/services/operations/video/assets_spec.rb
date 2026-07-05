# frozen_string_literal: true

require 'rails_helper'

# The video Assets tab: listing the created characters/scenarios/music, and
# regenerating a reference image (new image, no re-render).
RSpec.describe 'Video assets', type: :model do
  let(:user) { User.create!(email: 'assets@agencios.app', password: 'secret123', name: 'A') }
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
                                  provider: 'openrouter',
                                  params: { mode: 'character', aspect_ratio: '9:16',
                                            music_url: 'https://prov/song.mp3', music_title: 'Song', music_mood: 'calm',
                                            music_attribution: 'Song — Artist',
                                            identity: { 'has_character' => true, 'character' => 'A cheerful fox mascot',
                                                        'scenario' => 'A cozy kitchen' } })
  end

  before do
    Current.workspace = workspace
    Current.actor = user
    generation # materialize now that Current is set
  end

  after { Current.reset }

  # A scene carrying a generated character image + a scene image reference.
  def build_scene(position, urls, roles)
    creative.video_scenes.create!(workspace: workspace, position: position, mode: 'character',
                                  render_state: :ready, aspect_ratio: '9:16', duration_seconds: 8,
                                  prompt: "p#{position}", reference_image_urls: urls,
                                  metadata: { 'reference_roles' => roles })
  end

  describe Operations::Video::AssetList do
    it 'lists characters, scenarios, references and music from scenes + identity' do
      build_scene(0, ['https://cdn/fox.png', 'https://cdn/kitchen.png', 'https://cdn/logo.png'], %w[character scene logo])
      build_scene(1, ['https://cdn/fox.png'], %w[character])

      out = described_class.call(creative: creative.reload)

      expect(out[:characters].map { |a| a[:image_url] }).to eq(['https://cdn/fox.png']) # deduped
      expect(out[:characters].first).to include(role: 'character', role_label: 'Personagem', description: 'A cheerful fox mascot')
      expect(out[:scenarios].map { |a| a[:image_url] }).to eq(['https://cdn/kitchen.png'])
      expect(out[:references].map { |a| a[:role] }).to eq(['logo'])
      expect(out[:references].first).to include(role_label: 'Logo', image_url: 'https://cdn/logo.png')
      expect(out[:music]).to include(title: 'Song', mood: 'calm', url: 'https://prov/song.mp3')
    end

    it 'prefers a stored PT description over the identity text' do
      build_scene(0, ['https://cdn/fox.png'], %w[character])
      generation.update!(params: generation.params.merge('asset_descriptions' => { 'https://cdn/fox.png' => 'Uma raposa prateada' }))

      out = described_class.call(creative: creative.reload)
      expect(out[:characters].first[:description]).to eq('Uma raposa prateada')
    end

    it 'falls back to a text-only asset when the identity describes a role with no image' do
      build_scene(0, [], [])

      out = described_class.call(creative: creative.reload)

      expect(out[:characters]).to eq([{ key: 'identity:character', role: 'character', role_label: 'Personagem',
                                        image_url: nil, kind: nil, description: 'A cheerful fox mascot' }])
      expect(out[:scenarios].first).to include(key: 'identity:scenario', image_url: nil)
    end
  end

  describe Operations::Video::RegenerateReference do
    before do
      allow(Operations::Video::GenerateReference).to receive(:call).and_return({ url: 'https://cdn/fox-v2.png', role: 'character' })
      allow(Operations::Video::RenderScene).to receive(:call)
    end

    it 'swaps the image across every scene WITHOUT re-rendering, and updates the identity' do
      s0 = build_scene(0, ['https://cdn/fox.png', 'https://cdn/kitchen.png'], %w[character scene])
      s1 = build_scene(1, ['https://cdn/fox.png'], %w[character])

      described_class.call(creative: creative, role: 'character', prompt: 'A sleek silver fox', replace_url: 'https://cdn/fox.png')

      expect(s0.reload.reference_image_urls).to eq(['https://cdn/fox-v2.png', 'https://cdn/kitchen.png'])
      expect(s1.reload.reference_image_urls).to eq(['https://cdn/fox-v2.png'])
      expect(s0.render_state).to eq('ready') # not re-rendered
      expect(Operations::Video::RenderScene).not_to have_received(:call)
      expect(generation.reload.params.dig('identity', 'character')).to eq('A sleek silver fox')
    end

    it 'prepends the image as the role when there is nothing to replace' do
      s0 = build_scene(0, ['https://cdn/kitchen.png'], %w[scene])

      described_class.call(creative: creative, role: 'character', prompt: 'A new mascot')

      expect(s0.reload.reference_image_urls).to eq(['https://cdn/fox-v2.png', 'https://cdn/kitchen.png'])
      expect(s0.metadata['reference_roles']).to eq(%w[character scene])
    end

    it 'raises Invalid on a blank prompt' do
      expect { described_class.call(creative: creative, role: 'character', prompt: '  ') }
        .to raise_error(Operations::Errors::Invalid, /Descreva/)
    end

    it 'raises Invalid when the image generation yields nothing' do
      allow(Operations::Video::GenerateReference).to receive(:call).and_return(nil)
      expect { described_class.call(creative: creative, role: 'scene', prompt: 'A beach') }
        .to raise_error(Operations::Errors::Invalid, /imagem/)
    end
  end

  describe Operations::Video::AddReference do
    it 'prepends the element to every scene under its role (no re-render) and stores the PT description' do
      s0 = build_scene(0, ['https://cdn/kitchen.png'], %w[scene])
      s1 = build_scene(1, [], [])

      described_class.call(creative: creative, role: 'product', url: 'https://cdn/can.png', description: 'Lata prateada')

      expect(s0.reload.reference_image_urls).to eq(['https://cdn/can.png', 'https://cdn/kitchen.png'])
      expect(s0.metadata['reference_roles']).to eq(%w[product scene])
      expect(s1.reload.reference_image_urls).to eq(['https://cdn/can.png'])
      expect(generation.reload.params.dig('asset_descriptions', 'https://cdn/can.png')).to eq('Lata prateada')
    end

    it 'does not duplicate an element already on a scene' do
      s0 = build_scene(0, ['https://cdn/can.png'], %w[product])
      described_class.call(creative: creative, role: 'product', url: 'https://cdn/can.png')
      expect(s0.reload.reference_image_urls).to eq(['https://cdn/can.png'])
    end
  end

  describe Operations::Video::RemoveReference do
    it 'drops the reference from every scene, keeping roles aligned' do
      s0 = build_scene(0, ['https://cdn/fox.png', 'https://cdn/kitchen.png'], %w[character scene])

      described_class.call(creative: creative, key: 'https://cdn/fox.png')

      expect(s0.reload.reference_image_urls).to eq(['https://cdn/kitchen.png'])
      expect(s0.metadata['reference_roles']).to eq(%w[scene])
    end

    it 'clears the identity field for an identity:<field> key' do
      build_scene(0, [], [])
      described_class.call(creative: creative, key: 'identity:scenario')
      expect(generation.reload.params['identity']).not_to include('scenario')
    end
  end
end
