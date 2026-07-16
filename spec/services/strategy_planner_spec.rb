# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'AI content-strategy planning' do
  before do
    ActiveJob::Base.queue_adapter = :test
    @user, @workspace = Operations::Users::Register.call(
      email: 'sp@agencios.app', password: 'secret123', name: 'SP', workspace_name: 'SP Agency'
    )
    Current.workspace = @workspace
    Current.membership = @workspace.memberships.find_by(user: @user)
    @client = @workspace.clients.create!(name: 'ACME')
    @project = @workspace.projects.create!(client: @client, name: 'Camp', color: '#7C3AED')
    allow(Broadcaster).to receive(:board)
    allow(Broadcaster).to receive(:ticket)
    allow(Broadcaster).to receive(:strategy_session)
    allow(Operations::Push::Notify).to receive(:call)
  end

  after { Current.reset }

  # A deterministic plan so Apply is tested independently of the model.
  def sample_plan(post_at)
    {
      'summary' => 'Plano de teste',
      'tickets' => [
        {
          'title' => 'Reel semanal',
          'creative_type' => 'reel',
          'channels' => %w[instagram],
          'priority' => 'high',
          'scheduled_at' => post_at.iso8601,
          'brief' => 'Foco em educação.',
          'objective' => 'Educar sobre o produto.',
          'target_persona' => 'Jovens 18-24.',
          'content_pillar' => 'educacional',
          'format_hypothesis' => 'Reel de 30s.',
          'subtasks' => [
            { 'title' => 'Roteiro', 'estimate_hours' => 2, 'lead_offset_days' => 5 },
            { 'title' => 'Gravação', 'estimate_hours' => 4, 'lead_offset_days' => 2 }
          ]
        }
      ]
    }
  end

  describe 'Operations::Strategy::Start' do
    it 'finds or creates a single active session per project' do
      s1 = Operations::Strategy::Start.call(project: @project, user: @user)
      s2 = Operations::Strategy::Start.call(project: @project, user: @user)
      expect(s1.id).to eq(s2.id)
      expect(s1.status).to eq('active')
    end

    it 'RESUMES a proposed session instead of creating a new empty one' do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      session.update!(status: 'proposed', proposed_plan: sample_plan(10.days.from_now.change(hour: 10)))

      resumed = Operations::Strategy::Start.call(project: @project, user: @user)
      expect(resumed.id).to eq(session.id)
      expect(@project.strategy_sessions.count).to eq(1)
    end

    it 'is ETERNAL: resumes the same session (with its memory) after a legacy applied/discarded state' do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      session.push_message(role: :user, content: 'lembra: tom fofo, nada polêmico')
      session.update!(status: 'applied')

      resumed = Operations::Strategy::Start.call(project: @project, user: @user)
      expect(resumed.id).to eq(session.id)
      expect(resumed.status).to eq('active')
      expect(resumed.messages.map { |m| m['content'] }).to include('lembra: tom fofo, nada polêmico')
      expect(@project.strategy_sessions.count).to eq(1)
    end
  end

  describe 'Controllers::Strategy::Show' do
    it 'surfaces THE (single) session with its pending proposal' do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      session.update!(status: 'proposed', proposed_plan: sample_plan(10.days.from_now.change(hour: 10)))

      params = ActionController::Parameters.new(project_id: @project.id)
      result = Controllers::Strategy::Show.call(params: params)
      expect(result[:strategy_session][:id]).to eq(session.id)
      expect(result[:strategy_session][:status]).to eq('proposed')
      expect(result[:strategy_session][:proposed_plan]['tickets'].size).to eq(1)
    end
  end

  describe 'Controllers::Strategy::Discard' do
    it 'drops the pending proposal but keeps the session alive (eternal)' do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      session.push_message(role: :user, content: 'contexto importante')
      session.update!(status: 'proposed', proposed_plan: sample_plan(10.days.from_now.change(hour: 10)))

      params = ActionController::Parameters.new(id: session.id)
      Controllers::Strategy::Discard.call(params: params)

      session.reload
      expect(session.status).to eq('active')
      expect(session.proposed_plan).to eq({})
      expect(session.messages.map { |m| m['content'] }).to include('contexto importante')
      # The next open resumes this same session, memory intact.
      expect(Operations::Strategy::Start.call(project: @project, user: @user).id).to eq(session.id)
    end
  end

  describe 'Operations::Strategy::Converse' do
    it 'streams the reply, appends the transcript, and hands plan generation to a job' do
      session = Operations::Strategy::Start.call(project: @project, user: @user)

      # The stream carries only the chat text; the heavy plan decision + build runs
      # off the request (enqueued as a job), so Converse itself proposes nothing.
      fake = Vendors::Ai::StreamResult.new(
        text: 'Aqui está o plano.', tools: [],
        usage: { 'input_tokens' => 10, 'output_tokens' => 5 }, model: 'claude-sonnet-4-6'
      )
      client = instance_double(Vendors::OpenRouter::Client, provider_key: AiUsageLog::PROVIDER_OPENROUTER)
      allow(Vendors::Ai).to receive(:client).and_return(client)
      allow(client).to receive(:stream) do |**_kw, &blk|
        blk&.call('Aqui ')
        blk&.call('está o plano.')
        fake
      end

      chunks = []
      result = nil
      expect do
        result = Operations::Strategy::Converse.call(session: session, content: '1 reel por semana') { |c| chunks << c }
      end.to have_enqueued_job(Strategy::PlanTurnJob).with(session.id)

      expect(chunks.join).to eq('Aqui está o plano.')
      expect(result.proposal).to be_nil
      session.reload
      # Converse only advances the conversation — the plan job flips the status.
      expect(session.status).to eq('active')
      # Leading assistant turn is the opening message from Start.
      expect(session.messages.map { |m| m['role'] }).to eq(%w[assistant user assistant])
    end
  end

  # A slim proposed card — only the approval-visible fields the planner produces.
  def slim_card(key, post_at, title: 'Reel semanal', type: 'reel', channels: %w[instagram])
    { 'key' => key, 'title' => title, 'creative_type' => type, 'channels' => channels,
      'priority' => 'high', 'scheduled_at' => post_at.iso8601, 'state' => 'ready' }
  end

  def proposed_with(*cards)
    { 'summary' => 'Plano de teste', 'tickets' => cards }
  end

  describe 'Operations::Strategy::GeneratePlan' do
    it 'streams the batch card by card, keys each card, and marks the session proposed' do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      session.push_message(role: :user, content: '1 reel por semana')
      session.save!
      post_at = 10.days.from_now.change(hour: 10)

      client = instance_double(Vendors::OpenRouter::Client, provider_key: AiUsageLog::PROVIDER_OPENROUTER)
      allow(Vendors::Ai).to receive(:client).and_return(client)
      # Slim plan tool → one card (no brief/subtasks; those come at ticket creation).
      allow(client).to receive(:generate).and_return(
        Vendors::Ai::Result.new(
          text: '', tool_input: { 'summary' => 'Plano', 'tickets' => [slim_card(nil, post_at).except('key', 'state')] },
          usage: { 'input_tokens' => 20, 'output_tokens' => 40 }, model: 'claude-sonnet-4-6'
        )
      )
      stub_const('Operations::Strategy::GeneratePlan::STAGGER', 0) # no per-card sleep in tests

      Operations::Strategy::GeneratePlan.call(session: session)

      session.reload
      expect(session.status).to eq('proposed')
      card = session.proposed_plan['tickets'].first
      expect(card['key']).to eq('t1')
      expect(card['state']).to eq('ready')
      # The live sequence the table renders: loading → empty rows → each row fills → done.
      expect(Broadcaster).to have_received(:strategy_session).with(session, 'plan_started')
      expect(Broadcaster).to have_received(:strategy_session).with(session, 'plan_outline', hash_including(:tickets))
      expect(Broadcaster).to have_received(:strategy_session).with(session, 'ticket_drafted', hash_including(key: 't1'))
      expect(Broadcaster).to have_received(:strategy_session).with(session, 'plan_ready')
    end
  end

  describe 'Operations::Strategy::ResolveTurn' do
    def stub_action(action)
      client = instance_double(Vendors::OpenRouter::Client, provider_key: AiUsageLog::PROVIDER_OPENROUTER)
      allow(Vendors::Ai).to receive(:client).and_return(client)
      allow(client).to receive(:generate).and_return(
        Vendors::Ai::Result.new(text: '', tool_input: action, usage: {}, model: 'm')
      )
      client
    end

    it 'dispatches generate_plan to GeneratePlan' do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      stub_action('action' => 'generate_plan')
      expect(Operations::Strategy::GeneratePlan).to receive(:call).with(session: session)
      Operations::Strategy::ResolveTurn.call(session: session)
    end

    it 'dispatches revise_ticket to ReviseTicket with the key + instruction' do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      stub_action('action' => 'revise_ticket', 'ticket_key' => 't2', 'instruction' => 'mais leve')
      expect(Operations::Strategy::ReviseTicket).to receive(:call)
        .with(session: session, key: 't2', instruction: 'mais leve')
      Operations::Strategy::ResolveTurn.call(session: session)
    end

    it 'settles the waiting UI on wait (turn_wait), building nothing' do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      stub_action('action' => 'wait')
      expect(Operations::Strategy::GeneratePlan).not_to receive(:call)
      expect(Operations::Strategy::ReviseTicket).not_to receive(:call)
      Operations::Strategy::ResolveTurn.call(session: session)
      expect(Broadcaster).to have_received(:strategy_session).with(session, 'turn_wait')
    end

    it 'dispatches remove_ticket to RemoveTicket with the key' do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      stub_action('action' => 'remove_ticket', 'ticket_key' => '#42')
      expect(Operations::Strategy::RemoveTicket).to receive(:call).with(session: session, key: '#42')
      Operations::Strategy::ResolveTurn.call(session: session)
    end

    it 'REFUSES generate_plan on a campaign that already has tickets — with a LIVE explanation, never silently' do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      Operations::Tickets::Create.call(
        workspace: @workspace, user: @user, params: { project_id: @project.id, title: 'Já existe' }
      )
      stub_action('action' => 'generate_plan')
      expect(Operations::Strategy::GeneratePlan).not_to receive(:call)
      Operations::Strategy::ResolveTurn.call(session: session)

      # The refusal reaches the user: an assistant note in the transcript + live.
      expect(session.reload.messages.last['content']).to include('não vou refazer o plano')
      expect(Broadcaster).to have_received(:strategy_session)
        .with(session, 'assistant_note', hash_including(:content))
    end
  end

  describe 'Operations::Strategy::ReviseTicket' do
    it 'regenerates only the targeted card and broadcasts revising → drafted' do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      post_at = 10.days.from_now.change(hour: 10)
      session.update!(status: 'proposed',
                      proposed_plan: proposed_with(slim_card('t1', post_at, title: 'Rinoceronte'),
                                                   slim_card('t2', post_at, title: 'Tartaruga')))

      client = instance_double(Vendors::OpenRouter::Client, provider_key: AiUsageLog::PROVIDER_OPENROUTER)
      allow(Vendors::Ai).to receive(:client).and_return(client)
      allow(client).to receive(:generate).and_return(
        Vendors::Ai::Result.new(text: '', model: 'm', usage: {},
                                tool_input: slim_card('ignored', post_at, title: 'Rinoceronte gentil').except('key', 'state'))
      )

      Operations::Strategy::ReviseTicket.call(session: session, key: 't1', instruction: 'mais gentil')

      cards = session.reload.proposed_plan['tickets']
      # Only t1 changed; t2 untouched; keys preserved.
      expect(cards.find { |c| c['key'] == 't1' }['title']).to eq('Rinoceronte gentil')
      expect(cards.find { |c| c['key'] == 't2' }['title']).to eq('Tartaruga')
      expect(Broadcaster).to have_received(:strategy_session).with(session, 'ticket_revising', key: 't1')
      expect(Broadcaster).to have_received(:strategy_session).with(session, 'ticket_drafted', hash_including(key: 't1'))
    end

    it 'ignores an unknown key' do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      session.update!(status: 'proposed', proposed_plan: proposed_with(slim_card('t1', 5.days.from_now)))
      Operations::Strategy::ReviseTicket.call(session: session, key: 'nope', instruction: 'x')
      expect(Broadcaster).not_to have_received(:strategy_session)
    end
  end

  describe 'Operations::Strategy::Apply' do
    it 'materializes each SLIM card and defers the brief/checklist to a per-ticket job' do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      # Relative (never a fixed calendar date): Apply clamps past dates to "now",
      # so a hardcoded date rots into a false failure once the calendar passes it.
      post_at = 2.days.from_now.change(hour: 10)
      session.update!(status: 'proposed', proposed_plan: proposed_with(slim_card('t1', post_at)))

      tickets = nil
      expect { tickets = Operations::Strategy::Apply.call(session: session, user: @user) }
        .to change { @workspace.tickets.count }.by(1)

      ticket = tickets.first
      # The plan delimits the strategy: creative type + channels + date come from it.
      expect(ticket.creative_type).to eq('reel')
      expect(ticket.channels).to eq(%w[instagram])
      expect(ticket.priority).to eq('high')
      expect(ticket.scheduled_at).to eq(post_at)
      expect(ticket.status).to eq('ideation')
      # The brief + checklist are NOT in the plan — they're filled at creation, async.
      expect(ticket.fields_for('ideation')['brief']).to be_blank
      expect(ticket.subtasks).to be_empty
      expect(Strategy::FillTicketJob).to have_been_enqueued.with(ticket.id)
      # The session is eternal — applying returns it to `active` (conversing).
      expect(session.reload.status).to eq('active')
    end

    it 'links created tickets to the session' do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      session.update!(status: 'proposed', proposed_plan: sample_plan(10.days.from_now.change(hour: 10)))
      ticket = Operations::Strategy::Apply.call(session: session, user: @user).first
      expect(ticket.strategy_session_id).to eq(session.id)
      expect(session.tickets).to contain_exactly(ticket)
    end

    it 'rewrites from scratch on re-apply: replaces the previous batch, no duplicates' do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      post_at = 10.days.from_now.change(hour: 10)
      session.update!(status: 'proposed', proposed_plan: sample_plan(post_at))

      first = Operations::Strategy::Apply.call(session: session, user: @user).first
      expect(@workspace.tickets.count).to eq(1)

      # Edit the plan (now two pieces) and re-apply.
      edited = sample_plan(post_at)
      edited['tickets'] << edited['tickets'].first.merge('title' => 'Carrossel semanal', 'creative_type' => 'carousel')
      session.update!(status: 'proposed', proposed_plan: edited)

      expect { Operations::Strategy::Apply.call(session: session, user: @user) }
        .to change { @workspace.tickets.count }.from(1).to(2)
      # The first batch was destroyed, not stacked alongside the new one.
      expect(Ticket.exists?(first.id)).to be(false)
      expect(@workspace.tickets.pluck(:strategy_session_id).uniq).to eq([session.id])
    end

    it 'leaves hand-made tickets untouched on re-apply' do
      manual = Operations::Tickets::Create.call(
        workspace: @workspace, user: @user, params: { project_id: @project.id, title: 'Feito à mão' }
      )
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      session.update!(status: 'proposed', proposed_plan: sample_plan(10.days.from_now.change(hour: 10)))
      Operations::Strategy::Apply.call(session: session, user: @user)
      session.update!(status: 'proposed') # simulate an edit round
      Operations::Strategy::Apply.call(session: session, user: @user)

      expect(Ticket.exists?(manual.id)).to be(true)
      expect(manual.reload.strategy_session_id).to be_nil
    end

    it 'refuses to apply without a proposed plan' do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      expect { Operations::Strategy::Apply.call(session: session, user: @user) }
        .to raise_error(Operations::Errors::Invalid)
    end

    it 'enqueues a fill job for every materialized ticket' do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      post_at = 10.days.from_now.change(hour: 10)
      session.update!(status: 'proposed',
                      proposed_plan: proposed_with(slim_card('t1', post_at), slim_card('t2', post_at)))

      tickets = Operations::Strategy::Apply.call(session: session, user: @user)
      expect(tickets.size).to eq(2)
      tickets.each { |t| expect(Strategy::FillTicketJob).to have_been_enqueued.with(t.id) }
    end

    it 'clamps a posting date beyond one month back into the horizon' do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      # The planner scheduled a piece two months out — past the one-month limit.
      session.update!(status: 'proposed', proposed_plan: sample_plan(2.months.from_now.change(hour: 10)))

      ticket = Operations::Strategy::Apply.call(session: session, user: @user).first
      expect(ticket.scheduled_at).to be <= 1.month.from_now
    end
  end

  describe 'Operations::Strategy::Start opening message' do
    it 'seeds an assistant opening message on a fresh session' do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      expect(session.messages.size).to eq(1)
      expect(session.messages.first['role']).to eq('assistant')
      expect(session.messages.first['content']).to include(@client.name)
    end
  end

  describe 'derived overdue state' do
    it "flags a ticket whose posting date passed and isn't published yet" do
      ticket = Operations::Tickets::Create.call(
        workspace: @workspace, user: @user,
        params: { project_id: @project.id, title: 'Atrasado', scheduled_at: 2.days.ago }
      )
      expect(ticket.overdue?).to be(true)

      ticket.update!(status: :published)
      expect(ticket.overdue?).to be(false)
    end

    it 'flags an open subtask past its due date' do
      ticket = Operations::Tickets::Create.call(
        workspace: @workspace, user: @user, params: { project_id: @project.id, title: 'T' }
      )
      sub = Operations::Subtasks::Create.call(ticket: ticket, title: 'Late', due_date: 1.day.ago.to_date,
                                              estimate_hours: 3)
      expect(sub.overdue?).to be(true)
      sub.update!(done: true)
      expect(sub.overdue?).to be(false)
    end
  end
end
