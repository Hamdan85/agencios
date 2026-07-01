# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AI content-strategy planning" do
  before do
    ActiveJob::Base.queue_adapter = :test
    @user, @workspace = Operations::Users::Register.call(
      email: "sp@agencios.app", password: "secret123", name: "SP", workspace_name: "SP Agency"
    )
    Current.workspace = @workspace
    Current.membership = @workspace.memberships.find_by(user: @user)
    @client = @workspace.clients.create!(name: "ACME")
    @project = @workspace.projects.create!(client: @client, name: "Camp", color: "#7C3AED")
    allow(Broadcaster).to receive(:board)
    allow(Broadcaster).to receive(:ticket)
    allow(Operations::Push::Notify).to receive(:call)
  end

  after { Current.reset }

  # A deterministic plan so Apply is tested independently of the model.
  def sample_plan(post_at)
    {
      "summary" => "Plano de teste",
      "tickets" => [
        {
          "title" => "Reel semanal",
          "creative_type" => "reel",
          "channels" => %w[instagram],
          "priority" => "high",
          "scheduled_at" => post_at.iso8601,
          "brief" => "Foco em educação.",
          "objective" => "Educar sobre o produto.",
          "target_persona" => "Jovens 18-24.",
          "content_pillar" => "educacional",
          "format_hypothesis" => "Reel de 30s.",
          "subtasks" => [
            { "title" => "Roteiro", "estimate_hours" => 2, "lead_offset_days" => 5 },
            { "title" => "Gravação", "estimate_hours" => 4, "lead_offset_days" => 2 }
          ]
        }
      ]
    }
  end

  describe "Operations::Strategy::Start" do
    it "finds or creates a single active session per project" do
      s1 = Operations::Strategy::Start.call(project: @project, user: @user)
      s2 = Operations::Strategy::Start.call(project: @project, user: @user)
      expect(s1.id).to eq(s2.id)
      expect(s1.status).to eq("active")
    end

    it "RESUMES a proposed session instead of creating a new empty one" do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      session.update!(status: "proposed", proposed_plan: sample_plan(10.days.from_now.change(hour: 10)))

      resumed = Operations::Strategy::Start.call(project: @project, user: @user)
      expect(resumed.id).to eq(session.id)
      expect(@project.strategy_sessions.count).to eq(1)
    end
  end

  describe "Controllers::Strategy::Show" do
    it "surfaces a proposed plan even when a newer active session exists" do
      proposed = Operations::Strategy::Start.call(project: @project, user: @user)
      proposed.update!(status: "proposed", proposed_plan: sample_plan(10.days.from_now.change(hour: 10)))
      # A stray newer active session (the pre-fix bug) must not mask the plan.
      @project.strategy_sessions.create!(workspace: @workspace, user: @user, status: "active")

      params = ActionController::Parameters.new(project_id: @project.id)
      result = Controllers::Strategy::Show.call(params: params)
      expect(result[:strategy_session][:status]).to eq("proposed")
      expect(result[:strategy_session][:proposed_plan]["tickets"].size).to eq(1)
    end
  end

  describe "Operations::Strategy::Converse" do
    it "streams text, appends the transcript, and captures a proposed plan" do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      post_at = 10.days.from_now.change(hour: 10)

      fake = Vendors::Anthropic::Client::StreamResult.new(
        text: "Aqui está o plano.",
        tools: [{ name: Prompts::StrategyPlanner::TOOL_NAME, input: sample_plan(post_at) }],
        usage: { "input_tokens" => 10, "output_tokens" => 5 },
        model: "claude-sonnet-4-6"
      )
      client = instance_double(Vendors::Anthropic::Client)
      allow(Vendors::Anthropic::Client).to receive(:new).and_return(client)
      allow(client).to receive(:stream) do |**_kw, &blk|
        blk&.call("Aqui ")
        blk&.call("está o plano.")
        fake
      end

      chunks = []
      result = Operations::Strategy::Converse.call(session: session, content: "1 reel por semana") { |c| chunks << c }

      expect(chunks.join).to eq("Aqui está o plano.")
      expect(result.proposal["tickets"].size).to eq(1)
      session.reload
      expect(session.status).to eq("proposed")
      # Leading assistant turn is the opening message from Start.
      expect(session.messages.map { |m| m["role"] }).to eq(%w[assistant user assistant])
    end

    it "keeps asking (no proposal) when the model returns only text" do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      fake = Vendors::Anthropic::Client::StreamResult.new(
        text: "Quais redes?", tools: [], usage: {}, model: "claude-sonnet-4-6"
      )
      client = instance_double(Vendors::Anthropic::Client)
      allow(Vendors::Anthropic::Client).to receive(:new).and_return(client)
      allow(client).to receive(:stream).and_return(fake)

      result = Operations::Strategy::Converse.call(session: session, content: "quero postar")
      expect(result.proposal).to be_nil
      expect(session.reload.status).to eq("active")
    end
  end

  describe "Operations::Strategy::Apply" do
    it "creates scheduled tickets with back-scheduled, estimated subtasks" do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      post_at = Time.zone.parse("2026-07-15 10:00")
      session.update!(status: "proposed", proposed_plan: sample_plan(post_at))

      tickets = nil
      expect { tickets = Operations::Strategy::Apply.call(session: session, user: @user) }
        .to change { @workspace.tickets.count }.by(1)

      ticket = tickets.first
      # The plan delimits the strategy: creative type + channels come from it.
      expect(ticket.creative_type).to eq("reel")
      expect(ticket.channels).to eq(%w[instagram])
      expect(ticket.priority).to eq("high")
      expect(ticket.scheduled_at).to eq(post_at)
      # due_date is a scoping field — left blank; the posting date lives on scheduled_at.
      expect(ticket.due_date).to be_nil
      expect(ticket.status).to eq("ideation")
      ideation = ticket.fields_for("ideation")
      expect(ideation["brief"]).to eq("Foco em educação.")
      expect(ideation["objective"]).to eq("Educar sobre o produto.")
      expect(ideation["target_persona"]).to eq("Jovens 18-24.")
      expect(ideation["content_pillar"]).to eq("educacional")
      expect(ideation["format_hypothesis"]).to eq("Reel de 30s.")

      subs = ticket.subtasks.ordered.to_a
      expect(subs.map(&:title)).to eq(%w[Roteiro Gravação])
      expect(subs.first.due_date).to eq(post_at.to_date - 5) # lead_offset_days
      expect(subs.first.estimate_hours).to eq(2)
      expect(session.reload.status).to eq("applied")
    end

    it "links created tickets to the session" do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      session.update!(status: "proposed", proposed_plan: sample_plan(10.days.from_now.change(hour: 10)))
      ticket = Operations::Strategy::Apply.call(session: session, user: @user).first
      expect(ticket.strategy_session_id).to eq(session.id)
      expect(session.tickets).to contain_exactly(ticket)
    end

    it "rewrites from scratch on re-apply: replaces the previous batch, no duplicates" do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      post_at = 10.days.from_now.change(hour: 10)
      session.update!(status: "proposed", proposed_plan: sample_plan(post_at))

      first = Operations::Strategy::Apply.call(session: session, user: @user).first
      expect(@workspace.tickets.count).to eq(1)

      # Edit the plan (now two pieces) and re-apply.
      edited = sample_plan(post_at)
      edited["tickets"] << edited["tickets"].first.merge("title" => "Carrossel semanal", "creative_type" => "carousel")
      session.update!(status: "proposed", proposed_plan: edited)

      expect { Operations::Strategy::Apply.call(session: session, user: @user) }
        .to change { @workspace.tickets.count }.from(1).to(2)
      # The first batch was destroyed, not stacked alongside the new one.
      expect(Ticket.exists?(first.id)).to be(false)
      expect(@workspace.tickets.pluck(:strategy_session_id).uniq).to eq([session.id])
    end

    it "leaves hand-made tickets untouched on re-apply" do
      manual = Operations::Tickets::Create.call(
        workspace: @workspace, user: @user, params: { project_id: @project.id, title: "Feito à mão" }
      )
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      session.update!(status: "proposed", proposed_plan: sample_plan(10.days.from_now.change(hour: 10)))
      Operations::Strategy::Apply.call(session: session, user: @user)
      session.update!(status: "proposed") # simulate an edit round
      Operations::Strategy::Apply.call(session: session, user: @user)

      expect(Ticket.exists?(manual.id)).to be(true)
      expect(manual.reload.strategy_session_id).to be_nil
    end

    it "refuses to apply without a proposed plan" do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      expect { Operations::Strategy::Apply.call(session: session, user: @user) }
        .to raise_error(Operations::Errors::Invalid)
    end

    it "never back-schedules a task into the past" do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      # Posting in 2 days but a task needs 5 days of lead time → would land behind.
      plan = sample_plan(2.days.from_now.change(hour: 10))
      session.update!(status: "proposed", proposed_plan: plan)

      ticket = Operations::Strategy::Apply.call(session: session, user: @user).first
      expect(ticket.subtasks.minimum(:due_date)).to be >= Date.current
    end
  end

  describe "Operations::Strategy::Start opening message" do
    it "seeds an assistant opening message on a fresh session" do
      session = Operations::Strategy::Start.call(project: @project, user: @user)
      expect(session.messages.size).to eq(1)
      expect(session.messages.first["role"]).to eq("assistant")
      expect(session.messages.first["content"]).to include(@client.name)
    end
  end

  describe "derived overdue state" do
    it "flags a ticket whose posting date passed and isn't published yet" do
      ticket = Operations::Tickets::Create.call(
        workspace: @workspace, user: @user,
        params: { project_id: @project.id, title: "Atrasado", scheduled_at: 2.days.ago }
      )
      expect(ticket.overdue?).to be(true)

      ticket.update!(status: :published)
      expect(ticket.overdue?).to be(false)
    end

    it "flags an open subtask past its due date" do
      ticket = Operations::Tickets::Create.call(
        workspace: @workspace, user: @user, params: { project_id: @project.id, title: "T" }
      )
      sub = Operations::Subtasks::Create.call(ticket: ticket, title: "Late", due_date: 1.day.ago.to_date, estimate_hours: 3)
      expect(sub.overdue?).to be(true)
      sub.update!(done: true)
      expect(sub.overdue?).to be(false)
    end
  end
end
