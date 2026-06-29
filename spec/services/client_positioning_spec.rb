# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Client positioning AI threading" do
  let(:workspace) { Workspace.create!(name: "Agency", slug: "agency-test", brand_voice: "ousada") }
  let(:positioning) do
    {
      "statement" => "Para PMEs que querem vender mais, a marca é a parceira criativa.",
      "target_audience" => "PMEs de confeitaria",
      "content_pillars" => %w[bastidores dicas]
    }
  end

  before { Current.workspace = workspace }
  after { Current.reset }

  describe Operations::Clients::Create do
    it "persists a sanitized positioning bag" do
      client = described_class.call(
        name: "ACME",
        positioning: { "one_liner" => "  faz x ", "bogus" => "x", "content_pillars" => ["a", ""] }
      )

      expect(client.positioning).to eq("one_liner" => "faz x", "content_pillars" => %w[a])
      expect(client.positioning?).to be(true)
    end

    it "leaves positioning empty when none is given" do
      client = described_class.call(name: "No Pos")
      expect(client.positioning).to eq({})
    end
  end

  describe Prompts::Base, "#positioning_block" do
    it "renders the client positioning into a ticket-aware system prompt" do
      client = workspace.clients.create!(name: "ACME", positioning: positioning)
      builder = Prompts::TicketSummary.new(workspace:, client:, ticket: nil, status: "ideation")

      system = builder.system
      expect(system).to include("Posicionamento do cliente ACME")
      expect(system).to include("PMEs de confeitaria")
      expect(system).to include("bastidores; dicas")
    end

    it "renders nothing when the client has no positioning" do
      client = workspace.clients.create!(name: "Bare")
      builder = Prompts::TicketSummary.new(workspace:, client:, ticket: nil, status: "ideation")
      expect(builder.system).not_to include("Posicionamento do cliente")
    end
  end

  describe Operations::Ai::SummarizeTicket do
    it "threads the client positioning (via ticket.project.client) into the prompt" do
      client = workspace.clients.create!(name: "ACME", positioning: positioning)
      project = workspace.projects.create!(client:, name: "Camp", color: "#7C3AED")
      ticket = workspace.tickets.create!(project:, status: :ideation, title: "Reel")

      captured = nil
      allow(Broadcaster).to receive(:ticket)
      allow(AiAdapter).to receive(:complete) { |builder, **| captured = builder; "resumo" }

      described_class.call(ticket:)

      expect(captured.system).to include("Posicionamento do cliente ACME")
      expect(captured.system).to include("PMEs de confeitaria")
    end
  end

  describe Operations::Ai::SynthesizePositioning do
    it "returns a statement and pillars, parsing the model output" do
      allow(AiAdapter).to receive(:complete).and_return(
        "POSICIONAMENTO:\nPara PMEs que vendem doces, somos a parceira criativa.\n\nPILARES:\n- bastidores\n- dicas rápidas"
      )

      result = described_class.call(inputs: { "one_liner" => "doces" }, name: "ACME")

      expect(result[:statement]).to eq("Para PMEs que vendem doces, somos a parceira criativa.")
      expect(result[:content_pillars]).to eq(["bastidores", "dicas rápidas"])
    end

    it "degrades to the whole text as the statement when markers are absent" do
      allow(AiAdapter).to receive(:complete).and_return("texto livre sem marcadores")
      result = described_class.call(inputs: {}, name: "X")
      expect(result[:statement]).to eq("texto livre sem marcadores")
      expect(result[:content_pillars]).to eq([])
    end
  end
end
