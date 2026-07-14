# frozen_string_literal: true

require 'rails_helper'

# Image generation follows the project rule for ALL generation kinds: the
# request half (GenerateImage) is FAST — records + credit debit + enqueue — and
# the vendor render runs in Creatives::RenderImageJob → RenderImage, announcing
# the result over Action Cable. The vendor Action is stubbed so the spec stays
# offline.
RSpec.describe Operations::Creatives::GenerateImage do
  include ActiveJob::TestHelper

  let(:user) { User.create!(email: 'img@agencios.app', password: 'secret123', name: 'Img') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:ticket) do
    Operations::Tickets::Create.call(
      workspace: workspace, user: user,
      params: { project_id: project.id, title: 'Post', creative_type: 'feed_image', channels: %w[instagram] }
    )
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    Current.workspace = workspace
    Current.actor = user
    Operations::Credits::EnsureWallet.call(workspace: workspace).update!(purchased_balance: 1_000)
    allow(Vendors::OpenRouter::Actions::GenerateImage).to receive(:call)
      .and_return(bytes: 'PNGBYTES', content_type: 'image/png', cost_cents: 3.9, model: 'g/img')
  end

  after { Current.reset }

  it 'returns fast: creates the generating creative + processing generation, debits, enqueues the render job' do
    generation = described_class.call(ticket: ticket, prompt: 'a rocket')

    expect(generation).to have_attributes(kind: 'image', status: 'processing')
    expect(generation.creative.status).to eq('generating')
    expect(generation.params['prompt']).to be_present
    # NOTHING slow ran in-request.
    expect(Vendors::OpenRouter::Actions::GenerateImage).not_to have_received(:call)
    expect(Creatives::RenderImageJob).to have_been_enqueued.with(generation.id)

    debit = workspace.credit_transactions.debits.where(generation_id: generation.id).last
    expect(-debit.amount).to eq(Pricing.credits_for(kind: :image))
  end

  it 'fails + refunds and raises when the wallet cannot cover the debit' do
    Operations::Credits::EnsureWallet.call(workspace: workspace).update!(purchased_balance: 0)

    expect { described_class.call(ticket: ticket, prompt: 'x') }
      .to raise_error(Operations::Errors::InsufficientCredits)
    generation = workspace.generations.last
    expect(generation.status).to eq('failed')
    expect(Creatives::RenderImageJob).not_to have_been_enqueued
  end

  describe 'the render half (Operations::Creatives::RenderImage)' do
    it 'attaches the vendor result, finalizes both records and reports the rendered model' do
      generation = described_class.call(ticket: ticket, prompt: 'a rocket')

      Operations::Creatives::RenderImage.call(generation: generation)

      expect(generation.reload.status).to eq('completed')
      expect(generation.creative.reload.status).to eq('ready')
      expect(generation.creative.assets).to be_attached
      log = AiUsageLog.order(:id).last
      expect(log.operation).to eq('generate_image')
      expect(log.model).to eq('g/img')
    end

    it 'fails the generation and refunds on a vendor error' do
      generation = described_class.call(ticket: ticket, prompt: 'a rocket')
      allow(Vendors::OpenRouter::Actions::GenerateImage).to receive(:call)
        .and_raise(Vendors::Base::Error.new('boom', status: 500))

      expect { Operations::Creatives::RenderImage.call(generation: generation) }
        .to raise_error(Vendors::Base::Error)

      expect(generation.reload.status).to eq('failed')
      expect(generation.creative.reload.status).to eq('failed')
      refund = workspace.credit_transactions.where(generation_id: generation.id, kind: 'refund').last
      expect(refund.amount).to eq(Pricing.credits_for(kind: :image))
    end
  end

  describe 'the render job' do
    it 'skips a generation that is no longer processing (reaped/canceled)' do
      generation = described_class.call(ticket: ticket, prompt: 'x')
      Operations::Creatives::FailGeneration.call(generation: generation, reason: 'reaped')

      Creatives::RenderImageJob.perform_now(generation.id)

      expect(Vendors::OpenRouter::Actions::GenerateImage).not_to have_received(:call)
      expect(generation.reload.status).to eq('failed')
    end
  end
end
