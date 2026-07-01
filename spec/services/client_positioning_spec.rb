# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Client positioning AI threading' do
  let(:workspace) { Workspace.create!(name: 'Agency', slug: 'agency-test', brand_voice: 'ousada') }
  let(:positioning) do
    {
      'statement' => 'Para PMEs que querem vender mais, a marca é a parceira criativa.',
      'target_audience' => 'PMEs de confeitaria',
      'content_pillars' => %w[bastidores dicas]
    }
  end

  before { Current.workspace = workspace }
  after { Current.reset }

  describe Operations::Clients::Create do
    it 'persists a sanitized positioning bag' do
      client = described_class.call(
        name: 'ACME',
        positioning: { 'one_liner' => '  faz x ', 'bogus' => 'x', 'content_pillars' => ['a', ''] }
      )

      expect(client.positioning).to eq('one_liner' => 'faz x', 'content_pillars' => %w[a])
      expect(client.positioning?).to be(true)
    end

    it 'leaves positioning empty when none is given' do
      client = described_class.call(name: 'No Pos')
      expect(client.positioning).to eq({})
    end
  end

  describe Prompts::Base, '#positioning_block' do
    it 'renders the client positioning into a ticket-aware system prompt' do
      client = workspace.clients.create!(name: 'ACME', positioning: positioning)
      builder = Prompts::TicketSummary.new(workspace:, client:, ticket: nil, status: 'ideation')

      system = builder.system
      expect(system).to include('Posicionamento do cliente ACME')
      expect(system).to include('PMEs de confeitaria')
      expect(system).to include('bastidores; dicas')
    end

    it 'renders nothing when the client has no positioning' do
      client = workspace.clients.create!(name: 'Bare')
      builder = Prompts::TicketSummary.new(workspace:, client:, ticket: nil, status: 'ideation')
      expect(builder.system).not_to include('Posicionamento do cliente')
    end
  end

  describe Operations::Ai::SummarizeTicket do
    it 'threads the client positioning (via ticket.project.client) into the prompt' do
      client = workspace.clients.create!(name: 'ACME', positioning: positioning)
      project = workspace.projects.create!(client:, name: 'Camp', color: '#7C3AED')
      ticket = workspace.tickets.create!(project:, status: :ideation, title: 'Reel')

      captured = nil
      allow(Broadcaster).to receive(:ticket)
      allow(AiAdapter).to receive(:complete) { |builder, **|
        captured = builder
        'resumo'
      }

      described_class.call(ticket:)

      expect(captured.system).to include('Posicionamento do cliente ACME')
      expect(captured.system).to include('PMEs de confeitaria')
    end
  end

  describe Operations::Ai::SynthesizePositioning do
    it 'fills the structured fields from a free-text brief, parsing the JSON output' do
      allow(AiAdapter).to receive(:complete).and_return(
        <<~JSON
          Claro! Segue o posicionamento:
          {
            "one_liner": "Doces artesanais sob encomenda",
            "target_audience": "PMEs de confeitaria",
            "content_pillars": ["bastidores", "dicas rápidas"],
            "statement": "Para PMEs que vendem doces, somos a parceira criativa.",
            "bogus": "drop"
          }
        JSON
      )

      result = described_class.call(brief: 'Marca de doces para PMEs', name: 'ACME')

      expect(result['one_liner']).to eq('Doces artesanais sob encomenda')
      expect(result['target_audience']).to eq('PMEs de confeitaria')
      expect(result['content_pillars']).to eq(['bastidores', 'dicas rápidas'])
      expect(result['statement']).to eq('Para PMEs que vendem doces, somos a parceira criativa.')
      expect(result).not_to have_key('bogus')
    end

    it "degrades to seeding one_liner with the brief when the output isn't JSON" do
      allow(AiAdapter).to receive(:complete).and_return('[stub] texto livre sem json')
      result = described_class.call(brief: 'Uma marca incrível', name: 'X')
      expect(result['one_liner']).to eq('Uma marca incrível')
    end
  end

  describe Operations::Ai::ExtractClientFromUrl do
    let(:digest) do
      {
        url: 'https://docearte.com.br',
        title: 'Doce Arte | Confeitaria',
        site_name: 'Doce Arte',
        description: 'Bolos artesanais sob encomenda',
        theme_color: '#E91E63',
        emails: ['contato@docearte.com.br'],
        phones: ['+5511999998888'],
        socials: { instagram: 'https://instagram.com/docearte_oficial' },
        text: 'Bolos que encantam para festas e eventos.'
      }
    end

    before do
      allow_any_instance_of(Vendors::Web::Client).to receive(:fetch_digest).and_return(digest)
      allow_any_instance_of(Vendors::Web::Client).to receive(:fetch_image).and_return(nil)
    end

    it 'downloads the brand logo and returns it inline for the wizard' do
      digest[:logo_candidates] = ['https://docearte.com.br/logo.png']
      allow(AiAdapter).to receive(:complete).and_return('{ "contact": {}, "brand": {}, "positioning": {} }')
      allow_any_instance_of(Vendors::Web::Client).to receive(:fetch_image)
        .with('https://docearte.com.br/logo.png')
        .and_return(data_url: 'data:image/png;base64,AAAA', content_type: 'image/png', filename: 'logo.png')

      result = described_class.call(url: 'https://docearte.com.br')

      expect(result[:logo]).to include(
        data_url: 'data:image/png;base64,AAAA',
        filename: 'logo.png',
        source_url: 'https://docearte.com.br/logo.png'
      )
    end

    it 'extracts contact, brand and positioning from the model output' do
      allow(AiAdapter).to receive(:complete).and_return(
        <<~JSON
          {
            "contact": { "name": "Doce Arte", "company": "Doce Arte LTDA", "email": "", "phone": "" },
            "brand": { "brand_voice": "caloroso", "default_handle": "@docearte_oficial", "brand_primary_color": "E91E63" },
            "positioning": { "one_liner": "Bolos sob encomenda", "content_pillars": ["bastidores"], "bogus": "x" }
          }
        JSON
      )

      result = described_class.call(url: 'docearte.com.br')

      expect(result[:source_url]).to eq('https://docearte.com.br')
      expect(result[:contact]).to include(name: 'Doce Arte', company: 'Doce Arte LTDA')
      # Falls back to the digest's parsed signals when the model leaves a field blank.
      expect(result[:contact][:email]).to eq('contato@docearte.com.br')
      expect(result[:contact][:phone]).to eq('+5511999998888')
      expect(result[:brand]).to include(default_handle: 'docearte_oficial', brand_primary_color: '#e91e63')
      expect(result[:positioning]).to eq('one_liner' => 'Bolos sob encomenda', 'content_pillars' => %w[bastidores])
    end

    it 'falls back to the @handle and theme color parsed from the page' do
      allow(AiAdapter).to receive(:complete).and_return('{ "contact": {}, "brand": {}, "positioning": {} }')

      result = described_class.call(url: 'https://docearte.com.br')

      expect(result[:contact][:name]).to eq('Doce Arte')
      expect(result[:brand][:default_handle]).to eq('docearte_oficial')
      expect(result[:brand][:brand_primary_color]).to eq('#e91e63')
    end

    it "raises Invalid when the page can't be fetched" do
      allow_any_instance_of(Vendors::Web::Client)
        .to receive(:fetch_digest).and_raise(Vendors::Base::Error.new('Não foi possível acessar a página.'))

      expect { described_class.call(url: 'https://broken.example') }
        .to raise_error(Operations::Errors::Invalid, /não foi possível acessar/i)
    end

    it 'raises Invalid when no URL is given' do
      expect { described_class.call(url: '  ') }
        .to raise_error(Operations::Errors::Invalid, /informe a url/i)
    end
  end
end
