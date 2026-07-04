# frozen_string_literal: true

require 'rails_helper'

# The "melhorar esse prompt" wand: rewrites the draft video prompt with the
# brand + setup context (forced tool, stubbed here) and returns the improved
# PT-BR text; any AI failure surfaces as a clean Invalid.
RSpec.describe Operations::Ai::ImproveVideoPrompt do
  let(:user) { User.create!(email: 'wand@agencios.app', password: 'secret123', name: 'Wand') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }

  before do
    Current.workspace = workspace
    Current.actor = user
    allow(Operations::Ai::LogUsage).to receive(:call)
  end

  after { Current.reset }

  def stub_ai(tool_input)
    ai = instance_double('ai_client', provider_key: 'openrouter')
    allow(ai).to receive(:generate).and_return(
      Vendors::Ai::Result.new(text: '', usage: {}, model: 'x', tool_input: tool_input)
    )
    allow(Vendors::Ai).to receive(:client).and_return(ai)
    allow(Vendors::Ai).to receive(:model_for).and_return('x')
    ai
  end

  it 'returns the improved prompt, carrying the video setup into the system prompt' do
    ai = stub_ai('prompt' => 'Um reel vibrante mostrando o café gelado da ACME…')

    improved = described_class.call(
      workspace: workspace, user: user, client: client, mode: 'product',
      prompt: 'video do cafe', aspect_ratio: '9:16', duration: 16,
      with_audio: true, reference_count: 2, max_chars: 1000
    )

    expect(improved).to eq('Um reel vibrante mostrando o café gelado da ACME…')
    expect(ai).to have_received(:generate) do |args|
      expect(args[:system]).to include('PRODUCT', '9:16', '2 product reference photo(s)')
      expect(args[:prompt]).to include('video do cafe')
      expect(args[:tool]).to eq(Prompts::VideoPromptImprover.improve_tool)
    end
  end

  it 'truncates the improved prompt to max_chars' do
    stub_ai('prompt' => 'a' * 2000)

    improved = described_class.call(workspace: workspace, user: user, mode: 'avatar',
                                    prompt: 'rascunho', max_chars: 100)
    expect(improved.length).to eq(100)
  end

  it 'raises a clean Invalid when the AI errors (frontend restores the draft)' do
    allow(Vendors::Ai).to receive(:model_for).and_return('x')
    allow(Vendors::Ai).to receive(:client).and_raise(StandardError, 'boom')

    expect do
      described_class.call(workspace: workspace, user: user, mode: 'avatar', prompt: 'rascunho')
    end.to raise_error(Operations::Errors::Invalid, /Não foi possível melhorar/)
  end

  it 'raises Invalid when the tool returns a blank prompt' do
    stub_ai('prompt' => '  ')

    expect do
      described_class.call(workspace: workspace, user: user, mode: 'avatar', prompt: 'rascunho')
    end.to raise_error(Operations::Errors::Invalid)
  end
end
