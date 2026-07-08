# frozen_string_literal: true

require 'rails_helper'

# The conversational video editor turn: reads the message, asks the agent
# (forced tool, stubbed here), and applies per-scene edits through EditScene.
RSpec.describe Operations::Video::Chat::ResolveTurn do
  let(:user) { User.create!(email: 'chat@agencios.app', password: 'secret123', name: 'Chat') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:ticket) do
    Operations::Tickets::Create.call(
      workspace: workspace, user: user,
      params: { project_id: project.id, title: 'Reel', creative_type: 'ugc_video', channels: %w[instagram] }
    )
  end
  let(:creative) do
    Operations::Creatives::Create.call(ticket: ticket, creative_type: 'ugc_video',
                                       source: :generated, status: :ready, provider: 'openrouter')
  end
  let(:scene0) do
    Operations::Video::Scenes::Create.call(creative: creative, position: 0, mode: 'avatar',
                                           prompt: 'p0', duration_seconds: 8, aspect_ratio: '9:16')
                                     .tap { |s| s.update!(render_state: :ready) }
  end

  before do
    Current.workspace = workspace
    Current.actor = user
    allow(Operations::Ai::LogUsage).to receive(:call)
    allow(Operations::Video::EditScene).to receive(:call)
    # Voice discovery is a network call — keep it offline in chat-turn specs.
    allow(Vendors::Cartesia::Actions::ListVoices).to receive(:call).and_return([])
  end

  after { Current.reset }

  def stub_agent(tool_input)
    ai = instance_double('ai_client', provider_key: 'openrouter')
    allow(ai).to receive(:generate).and_return(
      Vendors::Ai::Result.new(text: '', usage: {}, model: 'x', tool_input: tool_input)
    )
    allow(Vendors::Ai).to receive(:client).and_return(ai)
    allow(Vendors::Ai).to receive(:model_for).and_return('x')
  end

  # ── Interview phase (before the video is generated) ──────────────────
  context 'interview phase (draft creative, no scenes yet)' do
    let(:draft) do
      Operations::Creatives::Create.call(ticket: ticket, creative_type: 'ugc_video',
                                         source: :generated, status: :draft, provider: 'openrouter',
                                         metadata: { 'phase' => 'interview', 'mode' => 'avatar',
                                                     'intake' => { 'brief' => 'reel do app', 'client_id' => client.id,
                                                                   'aspect_ratio' => '9:16', 'duration' => 8, 'with_audio' => true } })
    end

    it 'opens the interview on kickoff with a QUESTION and no user message stored' do
      stub_agent('action' => 'reply', 'message' => 'Qual é o objetivo do vídeo?')

      result = described_class.call(creative: draft, message: nil, kickoff: true)

      expect(result[:action]).to eq('reply')
      expect(draft.reload.chat_messages.map { |m| m['role'] }).to eq(%w[assistant]) # no user turn
      expect(result[:credits_spent]).to eq(0)
    end

    it 'launches generation (processing the CONSOLIDATED brief) when the agent returns generate' do
      allow(Operations::Creatives::GenerateUgcVideo).to receive(:call)
      stub_agent('action' => 'generate', 'message' => 'Fechado, gerando!',
                 'brief' => 'UGC avatar: founder explains the app, upbeat, CTA download')

      result = described_class.call(creative: draft, message: 'pode gerar')

      # The consolidated brief PLUS the user's original request (nothing lost).
      expect(Operations::Creatives::GenerateUgcVideo).to have_received(:call).with(
        hash_including(creative: draft, client_id: client.id, aspect_ratio: '9:16', duration: 8,
                       prompt: a_string_including('UGC avatar: founder explains the app', 'reel do app'))
      )
      expect(result[:reply]).to eq('Fechado, gerando!')
    end

    it 'falls back to the intake brief when the agent gives no consolidated brief' do
      allow(Operations::Creatives::GenerateUgcVideo).to receive(:call)
      stub_agent('action' => 'generate', 'message' => 'Gerando!')

      described_class.call(creative: draft, message: 'gera')

      expect(Operations::Creatives::GenerateUgcVideo).to have_received(:call).with(
        hash_including(creative: draft, prompt: 'reel do app')
      )
    end

    it 'refuses to generate again once scenes already exist' do
      Operations::Video::Scenes::Create.call(creative: draft, position: 0, mode: 'avatar',
                                             prompt: 'p0', duration_seconds: 8, aspect_ratio: '9:16')
      allow(Operations::Creatives::GenerateUgcVideo).to receive(:call)
      stub_agent('action' => 'generate', 'message' => 'Gerando!')

      result = described_class.call(creative: draft, message: 'gera de novo')

      expect(Operations::Creatives::GenerateUgcVideo).not_to have_received(:call)
      expect(result[:reply]).to match(/já está sendo montado/i)
    end
  end

  it 'edits the targeted scene when the agent returns an edit action' do
    scene0 # ensure the scene exists before the turn runs
    stub_agent('action' => 'edit', 'message' => 'Refazendo a cena 1.',
               'scenes' => [{ 'scene' => 1, 'prompt' => 'novo prompt' }])

    result = described_class.call(creative: creative, message: 'muda a abertura')

    expect(Operations::Video::EditScene).to have_received(:call).with(
      scene: scene0, caption: nil, prompt: 'novo prompt', camera: nil, dialogue: nil, sound_effects: nil,
      on_screen_text: nil, restyle: nil, add_reference_urls: [], reference_role: nil,
      reference_descriptions: {}
    )
    expect(result[:reply]).to eq('Refazendo a cena 1.')
    expect(creative.reload.chat_messages.map { |m| m['role'] }).to eq(%w[user assistant])
  end

  it 'reports the credits the turn spent (the UI shows them after the render lands, not in the reply)' do
    scene0
    Operations::Credits::EnsureWallet.call(workspace: workspace).update!(purchased_balance: 100)
    stub_agent('action' => 'edit', 'message' => 'Refazendo a cena 1.',
               'scenes' => [{ 'scene' => 1, 'prompt' => 'novo' }])
    # Simulate EditScene actually charging for the re-render.
    allow(Operations::Video::EditScene).to receive(:call) do
      Operations::Credits::Debit.call(workspace: workspace, amount: 5, description: 'Refazer cena 1 do vídeo')
    end

    result = described_class.call(creative: creative, message: 'muda')

    expect(result[:credits_spent]).to eq(5)
    # The reply stays clean — no cost text buried in the message.
    expect(result[:reply]).to eq('Refazendo a cena 1.')
  end

  it 'reports zero credits and appends no note when nothing re-renders' do
    stub_agent('action' => 'reply', 'message' => 'O vídeo tem 1 cena.')

    result = described_class.call(creative: creative, message: 'oi')

    expect(result[:credits_spent]).to eq(0)
    expect(result[:reply]).to eq('O vídeo tem 1 cena.')
  end

  it 'does not edit anything on a reply action' do
    stub_agent('action' => 'reply', 'message' => 'O vídeo tem 1 cena de 8s.')

    result = described_class.call(creative: creative, message: 'quantas cenas tem?')

    expect(Operations::Video::EditScene).not_to have_received(:call)
    expect(result[:reply]).to eq('O vídeo tem 1 cena de 8s.')
  end

  it 'removes a scene when the agent flags remove: true' do
    scene0
    scene1 = Operations::Video::Scenes::Create.call(creative: creative, position: 1, mode: 'avatar',
                                                    prompt: 'p1', duration_seconds: 8, aspect_ratio: '9:16')
    stub_agent('action' => 'edit', 'message' => 'Cortei a cena 2.',
               'scenes' => [{ 'scene' => 2, 'remove' => true }])
    allow(Operations::Video::RemoveScene).to receive(:call)

    described_class.call(creative: creative, message: 'corta a última cena')

    expect(Operations::Video::RemoveScene).to have_received(:call).with(scene: scene1)
    expect(Operations::Video::EditScene).not_to have_received(:call)
  end

  it 'adds a scene when the agent flags add: true' do
    scene0
    stub_agent('action' => 'edit', 'message' => 'Adicionando a cena final!',
               'scenes' => [{ 'scene' => 2, 'add' => true, 'prompt' => 'Closing logo shot', 'caption' => 'Final' }])
    allow(Operations::Video::AddScene).to receive(:call)

    described_class.call(creative: creative, message: 'adiciona uma cena final com a logo')

    expect(Operations::Video::AddScene).to have_received(:call).with(
      creative: creative, position: 1, prompt: 'Closing logo shot', caption: 'Final',
      camera: nil, dialogue: nil, sound_effects: nil, on_screen_text: nil, extra_reference_urls: [],
      reference_role: nil, reference_descriptions: {}
    )
    expect(Operations::Video::EditScene).not_to have_received(:call)
  end

  it 'moves a scene when the agent sets move_to' do
    scene0
    scene1 = Operations::Video::Scenes::Create.call(creative: creative, position: 1, mode: 'avatar',
                                                    prompt: 'p1', duration_seconds: 8, aspect_ratio: '9:16')
    stub_agent('action' => 'edit', 'message' => 'Movi a cena 2 para o início.',
               'scenes' => [{ 'scene' => 2, 'move_to' => 1 }])
    allow(Operations::Video::ReorderScene).to receive(:call)

    described_class.call(creative: creative, message: 'a cena 2 vem primeiro')

    expect(Operations::Video::ReorderScene).to have_received(:call).with(scene: scene1, to_position: 0)
  end

  it 'cancels the in-flight generation on a cancel action' do
    stub_agent('action' => 'cancel', 'message' => 'Cancelei a geração.')
    allow(Operations::Video::CancelRender).to receive(:call)

    result = described_class.call(creative: creative, message: 'para de gerar')

    expect(Operations::Video::CancelRender).to have_received(:call).with(creative: creative)
    expect(result[:reply]).to eq('Cancelei a geração.')
  end

  it 'threads attached reference images to the scene the agent edits' do
    scene0
    stub_agent('action' => 'edit', 'message' => 'Usando a referência na cena 1.',
               'scenes' => [{ 'scene' => 1, 'prompt' => 'match the attached product' }])

    described_class.call(creative: creative, message: 'usa essa foto',
                         reference_image_urls: ['https://cdn/x.jpg', ' '])

    expect(Operations::Video::EditScene).to have_received(:call).with(
      hash_including(scene: scene0, add_reference_urls: ['https://cdn/x.jpg'])
    )
  end

  it 'passes the role the agent declared for the attachment (typed reference)' do
    scene0
    stub_agent('action' => 'edit', 'message' => 'Aplicando o estilo na cena 1.',
               'reference_role' => 'style',
               'scenes' => [{ 'scene' => 1, 'prompt' => 'apply the style from img_style_v1' }])

    described_class.call(creative: creative, message: 'quero esse estilo',
                         reference_image_urls: ['https://cdn/style.jpg'])

    expect(Operations::Video::EditScene).to have_received(:call).with(
      hash_including(scene: scene0, add_reference_urls: ['https://cdn/style.jpg'],
                     reference_role: 'style')
    )
  end

  it 'stores structured per-scene annotations in the user message and hands them to the agent' do
    scene0
    captured = nil
    ai = instance_double('ai_client', provider_key: 'openrouter')
    allow(ai).to receive(:generate) do |**kwargs|
      captured = kwargs[:prompt]
      Vendors::Ai::Result.new(text: '', usage: {}, model: 'x', tool_input: {
                                'action' => 'edit', 'message' => 'Aplicando as notas.',
                                'scenes' => [{ 'scene' => 1, 'prompt' => 'novo' }]
                              })
    end
    allow(Vendors::Ai).to receive(:client).and_return(ai)
    allow(Vendors::Ai).to receive(:model_for).and_return('x')

    described_class.call(creative: creative, message: 'ajusta por favor',
                         annotations: [{ 'scene' => 1, 'note' => 'mais luz aqui' },
                                       { 'scene' => 99, 'note' => '' }])

    # The agent receives the notes as a structured block, each bound to ITS scene.
    expect(captured).to include('Per-scene annotations', 'Scene 1: mais luz aqui')
    # The history keeps the full instruction (message + notes) for later turns.
    stored = creative.reload.chat_messages.find { |m| m['role'] == 'user' }
    expect(stored['content']).to include('ajusta por favor', 'Cena 1: mais luz aqui')
  end

  it 'sends a balloon reference STRAIGHT to its scene even when the agent only replies' do
    scene0
    stub_agent('action' => 'reply', 'message' => 'Beleza!')

    described_class.call(creative: creative, message: 'usa essa referência na cena 1',
                         annotations: [{ 'scene' => 1, 'note' => 'esse é o cenário',
                                         'reference_urls' => ['https://cdn/scene.jpg'] }])

    expect(Operations::Video::EditScene).to have_received(:call).with(
      hash_including(scene: scene0, add_reference_urls: ['https://cdn/scene.jpg'])
    )
  end

  it 'threads a balloon reference into the agent edit of that same scene (no double apply)' do
    scene0
    stub_agent('action' => 'edit', 'message' => 'Ajustando a cena 1.',
               'scenes' => [{ 'scene' => 1, 'prompt' => 'novo' }])

    described_class.call(creative: creative, message: 'muda',
                         annotations: [{ 'scene' => 1, 'note' => 'x', 'reference_urls' => ['https://cdn/a.jpg'] }])

    # One EditScene for scene 1, carrying the balloon reference.
    expect(Operations::Video::EditScene).to have_received(:call).once.with(
      hash_including(scene: scene0, add_reference_urls: ['https://cdn/a.jpg'])
    )
  end

  it 'stamps the spent credits on the assistant bubble (UI shows −N under it)' do
    scene0
    Operations::Credits::EnsureWallet.call(workspace: workspace).update!(purchased_balance: 100)
    stub_agent('action' => 'edit', 'message' => 'Refazendo a cena 1.',
               'scenes' => [{ 'scene' => 1, 'prompt' => 'novo' }])
    allow(Operations::Video::EditScene).to receive(:call) do
      Operations::Credits::Debit.call(workspace: workspace, amount: 5, description: 'Refazer cena 1 do vídeo')
    end

    described_class.call(creative: creative, message: 'muda')

    last = creative.reload.chat_messages.last
    expect(last['role']).to eq('assistant')
    expect(last['credits']).to eq(5)
  end

  it 'leaves no credit stamp on a free (reply-only) turn' do
    scene0
    stub_agent('action' => 'reply', 'message' => 'O vídeo tem 1 cena.')

    described_class.call(creative: creative, message: 'oi')

    expect(creative.reload.chat_messages.last).not_to have_key('credits')
  end

  it 'explains a validation problem in the chat (not an error) instead of raising' do
    scene0
    stub_agent('action' => 'edit', 'message' => 'Adicionando a cena!',
               'scenes' => [{ 'scene' => 2, 'add' => true, 'prompt' => '' }])
    allow(Operations::Video::AddScene).to receive(:call)
      .and_raise(Operations::Errors::Invalid, 'A nova cena precisa de uma descrição')

    result = described_class.call(creative: creative, message: 'adiciona uma cena final')

    expect(result[:reply]).to match(/preciso saber o que deve aparecer|descrição/i)
    expect(result[:reply]).not_to eq('Adicionando a cena!') # the honest reply replaces the optimistic one
    expect(creative.reload.chat_messages.last['role']).to eq('assistant')
    expect(result[:credits_spent]).to eq(0)
  end

  it 'explains insufficient credits in the chat (the editor is past the billing gate)' do
    scene0
    stub_agent('action' => 'edit', 'message' => 'Refazendo.', 'scenes' => [{ 'scene' => 1, 'prompt' => 'novo' }])
    allow(Operations::Video::EditScene).to receive(:call).and_raise(Operations::Errors::InsufficientCredits)

    result = described_class.call(creative: creative, message: 'muda')

    expect(result[:reply]).to match(/crédito/i)
    expect(result[:reply]).to match(/Compre mais|assinatura/i)
    expect(result[:credits_spent]).to eq(0)
  end

  it 'changes the project identity when the agent returns an identity action' do
    scene0
    stub_agent('action' => 'identity', 'message' => 'Ajustando o figurino…',
               'identity' => { 'wardrobe' => 'social escuro' })
    allow(Operations::Video::SetIdentity).to receive(:call)

    result = described_class.call(creative: creative, message: 'muda o figurino pra social')

    expect(Operations::Video::SetIdentity).to have_received(:call)
      .with(creative: creative, changes: { 'wardrobe' => 'social escuro' })
    expect(result[:reply]).to eq('Ajustando o figurino…')
  end

  it 'changes the fixed voice when the agent returns a voice action' do
    scene0
    stub_agent('action' => 'voice', 'message' => 'Trocando a voz…', 'voice' => 'Feminina BR')
    allow(Operations::Video::SetVoice).to receive(:call)

    result = described_class.call(creative: creative, message: 'usa a voz feminina')

    expect(Operations::Video::SetVoice).to have_received(:call).with(creative: creative, voice: 'Feminina BR')
    expect(result[:reply]).to eq('Trocando a voz…')
  end

  it 'finalizes the approved draft when the agent returns a finalize action' do
    scene0
    stub_agent('action' => 'finalize', 'message' => 'Fechado! Gerando a versão final.')
    allow(Operations::Video::UpgradeQuality).to receive(:call)

    result = described_class.call(creative: creative, message: 'gostei, pode finalizar')

    expect(Operations::Video::UpgradeQuality).to have_received(:call).with(creative: creative)
    expect(Operations::Video::EditScene).not_to have_received(:call)
    expect(result[:reply]).to eq('Fechado! Gerando a versão final.')
  end

  it 'replies honestly when the finalize is blocked instead of claiming success' do
    stub_agent('action' => 'finalize', 'message' => 'Gerando a versão final!')
    allow(Operations::Video::UpgradeQuality).to receive(:call)
      .and_raise(Operations::Errors::Invalid, 'O vídeo ainda está em processamento')

    result = described_class.call(creative: creative, message: 'finaliza')

    expect(result[:reply]).to include('ainda está em processamento')
    expect(result[:reply]).not_to include('Gerando a versão final!')
  end

  it 'falls back to a safe reply when the agent errors' do
    allow(Vendors::Ai).to receive(:model_for).and_return('x')
    allow(Vendors::Ai).to receive(:client).and_raise(StandardError, 'boom')

    result = described_class.call(creative: creative, message: 'oi')

    expect(Operations::Video::EditScene).not_to have_received(:call)
    expect(result[:reply]).to be_present
    expect(creative.reload.chat_messages.last['role']).to eq('assistant')
  end
end
