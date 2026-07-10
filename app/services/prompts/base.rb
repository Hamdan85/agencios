# frozen_string_literal: true

module Prompts
  # Stateless AI prompt builders. Each exposes #system (the system prompt) and
  # reads brand context from the workspace + optional client positioning.
  class Base
    # PT-BR labels for the client positioning block injected into ticket-aware
    # prompts. Ordered: the distilled statement leads, then the supporting fields.
    POSITIONING_LABELS = {
      'statement' => 'Posicionamento',
      'one_liner' => 'O que faz',
      'category' => 'Categoria / mercado',
      'mission' => 'Missão',
      'target_audience' => 'Público-alvo',
      'audience_pain' => 'Dor da audiência',
      'value_proposition' => 'Proposta de valor',
      'differentiators' => 'Diferenciais',
      'competitors' => 'Concorrentes',
      'content_pillars' => 'Pilares de conteúdo',
      'keywords' => 'Palavras-chave',
      'guardrails' => 'Restrições / o que evitar'
    }.freeze

    def initialize(workspace: Current.workspace, client: nil, **context)
      @workspace = workspace
      @client = client
      @context = context
    end

    def system
      raise NotImplementedError
    end

    # Language names an LLM directive can point at unambiguously.
    LANGUAGE_NAMES = {
      'pt-BR' => 'português do Brasil (pt-BR)',
      'pt' => 'português (pt)',
      'en' => 'English (en-US)',
      'es' => 'español (es)'
    }.freeze

    private

    attr_reader :workspace, :client, :context

    # The language the model must WRITE in. Content prompts (captions, carousel
    # copy, scripts, storyboards) speak to the client's social-media AUDIENCE and
    # follow client.content_language; workspace-facing prompts (summaries,
    # retrospectives, audits) follow the workspace locale. Subclasses that
    # generate audience-facing content override `content_prompt?` to true.
    def response_language
      code = if content_prompt?
               client&.content_language.presence || workspace&.locale
             else
               workspace&.locale
             end
      code = code.presence || 'pt-BR'
      LANGUAGE_NAMES[code.to_s] || code.to_s
    end

    def content_prompt? = false

    # The standard output-language directive injected into every system prompt in
    # place of the old hardcoded "responda em português".
    def language_directive
      "Escreva TODO o texto voltado ao usuário em #{response_language}."
    end

    # Brand identity injected into every generative prompt. Uses the CLIENT's
    # brand when a client is in context (voice, @handle, colors), falling back to
    # the agency (workspace) defaults for any field the client leaves unset.
    def brand_block
      return '' unless workspace

      <<~TXT.strip
        Marca: #{client&.name.presence || workspace.name}
        Voz da marca: #{brand_voice}
        @handle padrão: #{brand_handle}
        Cores da marca: #{brand_colors}
      TXT
    end

    def brand_voice
      client&.brand_voice.presence || workspace.brand_voice.presence ||
        'tom profissional, próximo e criativo'
    end

    def brand_handle
      client&.default_handle.presence || workspace.default_handle.presence || '—'
    end

    def brand_colors
      primary = client&.brand_primary_color.presence || workspace.brand_primary_color
      secondary = client&.brand_secondary_color.presence || workspace.brand_secondary_color
      [primary, secondary].compact.join(' / ')
    end

    # The client's brand positioning, rendered as labeled lines. This is the
    # single seam that carries client-level context into every ticket AI task.
    # Returns "" when there is no client or no positioning captured yet.
    def positioning_block
      return '' unless client&.positioning?

      data = client.positioning
      lines = POSITIONING_LABELS.filter_map do |key, label|
        value = data[key]
        value = value.join('; ') if value.is_a?(Array)
        next if value.blank?

        "#{label}: #{value}"
      end
      return '' if lines.empty?

      <<~TXT.strip
        Posicionamento do cliente #{client.name} (use como contexto e respeite voz, público e diferenciais):
        #{lines.join("\n")}
      TXT
    end
  end
end
