# frozen_string_literal: true

require 'rails_helper'

# Carousel generations are one of the two usage-based billing meters
# (SPECIFICATION.md §9). On completion they must emit a Stripe meter event
# exactly once. The viral carousel writes its copy with Claude and rasterizes
# branded HTML slides — both are stubbed here so the spec stays offline.
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

  it 'meters a completed carousel to Stripe when the workspace has a customer' do
    workspace.subscription.update!(status: 'active', stripe_customer_id: 'cus_test')
    allow(Vendors::Stripe::Actions::ReportMeterEvent).to receive(:call).and_return(true)

    generation = described_class.call(ticket: ticket, slides: 3)

    expect(generation.kind).to eq('carousel')
    expect(generation.status).to eq('completed')
    expect(generation.metered_at).to be_present
    expect(generation.creative.assets.count).to eq(3)
    expect(Vendors::Stripe::Actions::ReportMeterEvent).to have_received(:call).once
  end

  it 'skips metering when the workspace has no Stripe customer yet' do
    allow(Vendors::Stripe::Actions::ReportMeterEvent).to receive(:call)

    generation = described_class.call(ticket: ticket, slides: 2)

    expect(generation.metered_at).to be_nil
    expect(Vendors::Stripe::Actions::ReportMeterEvent).not_to have_received(:call)
  end

  it 'marks the creative failed (never stranded in generating) when the render raises' do
    allow(Vendors::Render::Html).to receive(:batch).and_raise(
      Vendors::Render::Html::RenderError, 'Chromium down'
    )

    expect { described_class.call(ticket: ticket, slides: 3) }
      .to raise_error(Vendors::Render::Html::RenderError)

    creative = ticket.reload.creatives.where(source: Creative.sources[:generated]).last
    expect(creative.status).to eq('failed')
    expect(Generation.where(creative: creative)).to be_empty
  end
end
