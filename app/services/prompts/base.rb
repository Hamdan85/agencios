# frozen_string_literal: true

module Prompts
  # Stateless AI prompt builders. Each exposes #system (the system prompt) and
  # reads brand context from the workspace + optional client positioning.
  class Base
    # PT-BR labels for the client positioning block injected into ticket-aware
    # prompts. Ordered: the distilled statement leads, then the supporting fields.
    POSITIONING_LABELS = {
      "statement" => "Posicionamento",
      "one_liner" => "O que faz",
      "category" => "Categoria / mercado",
      "mission" => "Missão",
      "target_audience" => "Público-alvo",
      "audience_pain" => "Dor da audiência",
      "value_proposition" => "Proposta de valor",
      "differentiators" => "Diferenciais",
      "competitors" => "Concorrentes",
      "brand_voice" => "Voz da marca",
      "content_pillars" => "Pilares de conteúdo",
      "keywords" => "Palavras-chave",
      "guardrails" => "Restrições / o que evitar"
    }.freeze

    def initialize(workspace: Current.workspace, client: nil, **context)
      @workspace = workspace
      @client = client
      @context = context
    end

    def system
      raise NotImplementedError
    end

    private

    attr_reader :workspace, :client, :context

    def brand_block
      return "" unless workspace

      <<~TXT.strip
        Agência: #{workspace.name}
        Voz da marca: #{workspace.brand_voice.presence || "tom profissional, próximo e criativo"}
        @handle padrão: #{workspace.default_handle.presence || "—"}
      TXT
    end

    # The client's brand positioning, rendered as labeled lines. This is the
    # single seam that carries client-level context into every ticket AI task.
    # Returns "" when there is no client or no positioning captured yet.
    def positioning_block
      return "" unless client&.positioning?

      data = client.positioning
      lines = POSITIONING_LABELS.filter_map do |key, label|
        value = data[key]
        value = value.join("; ") if value.is_a?(Array)
        next if value.blank?

        "#{label}: #{value}"
      end
      return "" if lines.empty?

      <<~TXT.strip
        Posicionamento do cliente #{client.name} (use como contexto e respeite voz, público e diferenciais):
        #{lines.join("\n")}
      TXT
    end
  end
end
