# frozen_string_literal: true

require 'rails_helper'

# A carousel debits prepaid credits like an image (Pricing.credits_for(:carousel),
# default 1). The viral carousel writes its copy with the AI adapter and rasterizes
# branded HTML slides — both stubbed here so the spec stays offline.
RSpec.describe Operations::Creatives::GenerateViralCarousel do
  include ActiveJob::TestHelper

  let(:user) { User.create!(email: 'gen@agencios.app', password: 'secret123', name: 'Gen') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:ticket) do
    Operations::Tickets::Create.call(
      workspace: workspace, user: user,
      params: { project_id: project.id, title: 'Carrossel', creative_type: 'carousel', channels: %w[instagram] }
    )
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    Current.workspace = workspace
    Current.actor = user

    # Deterministic, image-free copy (no Pexels/Banana slots needed).
    slides_json = [
      { role: 'hook',  headline: 'Gancho', body: 'a', image: false, image_query: '' },
      { role: 'value', headline: 'Valor',  body: 'b', image: false, image_query: '' },
      { role: 'cta',   headline: 'CTA',    body: 'c', image: false, image_query: '' }
    ].to_json
    allow(AiAdapter).to receive(:complete).and_return(slides_json)

    # Stub the headless renderer so no Chromium is launched.
    allow(Vendors::Render::Html).to receive(:batch) { |htmls:, **_| htmls.map { 'PNGBYTES' } }
  end

  after { Current.reset }

  # Give the wallet a starting balance so the debit has something to draw from.
  def fund_wallet(credits)
    Operations::Credits::Grant.call(workspace: workspace, amount: credits, expires_at: 1.year.from_now)
  end

  it 'debits the configured carousel credits (default 1) from the wallet on completion' do
    fund_wallet(5)

    expect { described_class.call(ticket: ticket, slides: 3) }
      .to change { workspace.reload.credits_available }.by(-Pricing.credits_for(kind: :carousel))

    generation = Generation.last
    expect(generation.kind).to eq('carousel')
    expect(generation.status).to eq('completed')
    expect(generation.creative.assets.count).to eq(3)
  end

  it 'refunds the debited credit and fails the creative when the render raises' do
    fund_wallet(5)
    allow(Vendors::Render::Html).to receive(:batch).and_raise(
      Vendors::Render::Html::RenderError, 'Chromium down'
    )

    expect { described_class.call(ticket: ticket, slides: 3) }
      .to raise_error(Vendors::Render::Html::RenderError)

    expect(workspace.reload.credits_available).to eq(5) # debit refunded
    creative = ticket.reload.creatives.where(source: Creative.sources[:generated]).last
    expect(creative.status).to eq('failed')
    expect(Generation.last.status).to eq('failed')
  end
end
