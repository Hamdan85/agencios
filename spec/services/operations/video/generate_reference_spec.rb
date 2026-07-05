# frozen_string_literal: true

require 'rails_helper'

# Generates a consistency-anchor reference image (character/scenario) via Banana,
# charged as an image generation; best-effort (never fails the video).
RSpec.describe Operations::Video::GenerateReference do
  let(:user) { User.create!(email: 'gr@agencios.app', password: 'secret123', name: 'GR') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:creative) do
    ticket = begin
      project = workspace.projects.create!(client: workspace.clients.create!(name: 'ACME'), name: 'C', color: '#7C3AED')
      Operations::Tickets::Create.call(workspace: workspace, user: user,
                                       params: { project_id: project.id, title: 'Reel', creative_type: 'ugc_video', channels: %w[instagram] })
    end
    Operations::Creatives::Create.call(ticket: ticket, creative_type: 'ugc_video', source: :generated,
                                       status: :generating, provider: 'openrouter')
  end
  let(:generation) do
    workspace.generations.create!(user: user, creative: creative, kind: :video, status: :processing, provider: 'openrouter', params: {})
  end

  before do
    Current.workspace = workspace
    Current.actor = user
    Operations::Credits::EnsureWallet.call(workspace: workspace).update!(purchased_balance: 1000)
  end

  after { Current.reset }

  it 'generates via Banana, charges an image credit, stores it, and returns { url, role }' do
    allow(Vendors::Google::Banana::Actions::GenerateImage).to receive(:call)
      .and_return({ bytes: 'IMG', content_type: 'image/jpeg' })

    result = nil
    expect { result = described_class.call(generation: generation, role: 'character', prompt: 'a cheetah lawyer') }
      .to change { workspace.credit_wallet.reload.available }.by(-Pricing.credits_for(kind: :image))

    expect(result[:role]).to eq('character')
    expect(result[:url]).to include('/rails/')
    # A character sheet is requested square.
    expect(Vendors::Google::Banana::Actions::GenerateImage).to have_received(:call)
      .with(hash_including(aspect_ratio: '1:1'))
  end

  it 'refunds and returns nil when Banana fails (never blocks the video)' do
    allow(Vendors::Google::Banana::Actions::GenerateImage).to receive(:call).and_raise(StandardError, 'boom')

    result = nil
    expect { result = described_class.call(generation: generation, role: 'scene', prompt: 'an office', aspect_ratio: '9:16') }
      .not_to(change { workspace.credit_wallet.reload.available })
    expect(result).to be_nil
  end

  it 'is a no-op for a blank prompt' do
    expect(described_class.call(generation: generation, role: 'character', prompt: '  ')).to be_nil
  end
end
