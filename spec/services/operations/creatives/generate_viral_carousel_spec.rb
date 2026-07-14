# frozen_string_literal: true

require 'rails_helper'

# Carousel generation follows the project rule for ALL generation kinds: the
# request half (GenerateViralCarousel) is FAST — records + credit debit +
# enqueue — and the copy AI + Chromium render run in Creatives::RenderCarouselJob
# → RenderCarousel, announcing the result over Action Cable. The AI + renderer
# boundaries are stubbed so the spec stays offline.
RSpec.describe Operations::Creatives::GenerateViralCarousel do
  include ActiveJob::TestHelper

  let(:user) { User.create!(email: 'car@agencios.app', password: 'secret123', name: 'Car') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:ticket) do
    Operations::Tickets::Create.call(
      workspace: workspace, user: user,
      params: { project_id: project.id, title: 'Deck', creative_type: 'carousel', channels: %w[instagram] }
    )
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    Current.workspace = workspace
    Current.actor = user
    Operations::Credits::EnsureWallet.call(workspace: workspace).update!(purchased_balance: 1_000)
  end

  after { Current.reset }

  it 'returns fast: creates the generating creative + processing generation, debits, enqueues the render job' do
    generation = described_class.call(ticket: ticket, slides: 4, params: { topic: 'Vendas' })

    expect(generation).to have_attributes(kind: 'carousel', status: 'processing')
    expect(generation.creative.status).to eq('generating')
    expect(generation.params['slides']).to eq(4)
    expect(generation.params['topic']).to eq('Vendas')
    expect(Creatives::RenderCarouselJob).to have_been_enqueued.with(generation.id)

    debit = workspace.credit_transactions.debits.where(generation_id: generation.id).last
    expect(-debit.amount).to eq(Pricing.credits_for(kind: :carousel))
  end

  describe 'the render half (Operations::Creatives::RenderCarousel)' do
    before do
      allow(AiAdapter).to receive(:complete).and_return(
        [{ 'role' => 'hook', 'headline' => 'Título', 'body' => '' },
         { 'role' => 'value', 'headline' => 'Ponto', 'body' => '' },
         { 'role' => 'cta', 'headline' => 'CTA', 'body' => '' }].to_json
      )
      allow(Vendors::Render::Html).to receive(:batch) { |htmls:, **| htmls.map { 'PNGBYTES' } }
    end

    it 'renders the slides, finalizes both records and stores the slide metadata' do
      generation = described_class.call(ticket: ticket, slides: 3, params: { topic: 'Vendas' })

      Operations::Creatives::RenderCarousel.call(generation: generation)

      expect(generation.reload.status).to eq('completed')
      creative = generation.creative.reload
      expect(creative.status).to eq('ready')
      expect(creative.assets.attachments.size).to eq(3)
      expect(creative.metadata['slides'].size).to eq(3)
      expect(creative.metadata['slides'].first['url']).to be_present
    end

    it 'fails the generation and refunds on a renderer error' do
      generation = described_class.call(ticket: ticket, slides: 3, params: { topic: 'Vendas' })
      allow(Vendors::Render::Html).to receive(:batch).and_raise(StandardError, 'chromium down')

      expect { Operations::Creatives::RenderCarousel.call(generation: generation) }
        .to raise_error(StandardError, /chromium down/)

      expect(generation.reload.status).to eq('failed')
      expect(generation.creative.reload.status).to eq('failed')
      refund = workspace.credit_transactions.where(generation_id: generation.id, kind: 'refund').last
      expect(refund.amount).to eq(Pricing.credits_for(kind: :carousel))
    end
  end
end
