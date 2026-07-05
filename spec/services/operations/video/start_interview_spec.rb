# frozen_string_literal: true

require 'rails_helper'

# The studio "novo vídeo" flow opens a chat INTERVIEW instead of generating: a
# draft creative (no generation / no credit hold) whose chat opens with the
# agent's first question, produced by the SAME editor agent (kickoff turn).
RSpec.describe Operations::Video::StartInterview do
  let(:user) { User.create!(email: 'intake@agencios.app', password: 'secret123', name: 'Intake') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }

  before do
    Current.workspace = workspace
    Current.actor = user
    allow(Operations::Ai::LogUsage).to receive(:call)
    # The kickoff agent turn: with little context, it opens with a question.
    ai = instance_double('ai_client', provider_key: 'openrouter')
    allow(ai).to receive(:generate).and_return(
      Vendors::Ai::Result.new(text: '', usage: {}, model: 'x', tool_input: {
                                'action' => 'reply', 'message' => 'Boa! Qual é o objetivo do vídeo e quem vai assistir?'
                              })
    )
    allow(Vendors::Ai).to receive(:client).and_return(ai)
    allow(Vendors::Ai).to receive(:model_for).and_return('x')
  end

  after { Current.reset }

  it 'creates a DRAFT creative in the interview phase with the intake stored (no generation, no debit)' do
    creative = described_class.call(
      workspace: workspace, client_id: client.id, prompt: 'reel sobre o app',
      aspect_ratio: '9:16', duration: 8, with_audio: true, reference_image_urls: ['https://x/p.jpg']
    )

    expect(creative).to be_status_draft
    expect(creative.metadata['phase']).to eq('interview')
    expect(creative.metadata.dig('intake', 'brief')).to eq('reel sobre o app')
    expect(creative.metadata.dig('intake', 'reference_image_urls')).to eq(['https://x/p.jpg'])
    # References attached ⇒ the seeded mode leans product.
    expect(creative.metadata['mode']).to eq('product')
    expect(creative.generation).to be_nil
    expect(creative.video_scenes).to be_empty
    expect(workspace.credit_wallet&.reload&.available.to_i).to eq(0) # nothing debited
  end

  it 'opens the chat with the USER brief first, then the agent\'s QUESTION' do
    creative = described_class.call(workspace: workspace, client_id: client.id,
                                    prompt: 'reel sobre o app', duration: 8,
                                    reference_image_urls: ['https://x/ref.jpg'])

    msgs = creative.chat_messages
    expect(msgs.map { |m| m['role'] }).to eq(%w[user assistant])
    # The user's brief is the FIRST message, carrying its reference thumbnail.
    expect(msgs.first['content']).to eq('reel sobre o app')
    expect(msgs.first['images']).to eq(['https://x/ref.jpg'])
    # The agent responds with a question, not a "building" announcement.
    expect(msgs.last['role']).to eq('assistant')
    expect(msgs.last['content']).to include('objetivo')
    expect(msgs.last['content']).not_to match(/montando|gerando/i)
  end
end
