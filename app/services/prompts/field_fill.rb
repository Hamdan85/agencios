# frozen_string_literal: true

module Prompts
  # Status-aware "fill the current phase's fields" prompt. Given everything the
  # team has already produced in the earlier funnel stages (carried in via
  # `ctx`), Claude fills the fillable fields of the ticket's current status via
  # a forced tool call (Operations::Ai::FillFields reads the structured
  # `tool_input`, never freeform text). Drives the per-phase "Gerar com IA"
  # action.
  #
  # Only *content* fields are AI-fillable — human decisions (dates, switches,
  # approval status, the channel selection) are intentionally excluded.
  class FieldFill < Base
    TOOL_NAME = 'fill_ticket_fields'

    # Per-status field descriptions, used both as the tool's input_schema
    # property descriptions and to build `system`'s task framing.
    SPECS = {
      'ideation' => {
        'objective' => 'Objetivo claro do conteúdo, em uma frase',
        'target_persona' => 'Persona-alvo específica (quem queremos impactar), em uma frase',
        'content_pillar' => 'Pilar de conteúdo em poucas palavras (ex.: bastidores, educacional)',
        'format_hypothesis' => 'Hipótese de formato (ex.: Reel narrativo de 30s)'
      },
      'scoping' => {
        'copy_brief' => 'Direção de mensagem para a legenda, 2 a 3 frases',
        'script' => 'Roteiro/storyboard enxuto do conteúdo',
        'deliverables' => 'Lista de entregáveis concretos',
        'effort_estimate' => 'Estimativa de esforço (ex.: 4h, 2 dias)'
      },
      'production' => {
        'caption' => 'Legenda final pronta para publicar: gancho na 1ª linha, corpo curto e CTA',
        'hashtags' => 'Hashtags relevantes SEM o # (5 a 12)',
        'internal_notes' => 'Observações de produção para a equipe (HTML simples: <p>, <ul>, <li>, <strong>)'
      },
      'scheduled' => {
        'captions' => 'Uma legenda final por canal conectado, cada uma otimizada para as ' \
                      'convenções e limites daquela rede (ver regras por rede)',
        'first_comment' => 'Primeiro comentário a fixar no post (hashtags extras / contexto)'
      },
      'retrospective' => {
        'wins' => 'O que funcionou bem',
        'improvements' => 'O que pode melhorar no próximo ciclo',
        'lessons_learned' => 'Aprendizado consolidado em HTML simples (<p>, <ul>, <li>, <strong>)',
        'repeat_recommendation' => 'Recomendação — repeat (repetir), iterate (repetir com ajustes) ou retire (não repetir)'
      }
    }.freeze

    ARRAY_FIELDS = %w[deliverables wins improvements hashtags].freeze

    NETWORK_CAPTION_RULES = {
      'instagram' => 'gancho impactante na 1ª linha (aparece antes do "ver mais"), corpo curto, CTA; ' \
                     'hashtags vão no primeiro comentário, não repita aqui',
      'facebook' => 'pode ser mais longo e descritivo que o Instagram, tom de conversa, CTA claro com link se houver',
      'tiktok' => 'muito curto e direto, tom espontâneo, hashtags inline no fim (2 a 4)',
      'youtube' => 'título-e-descrição em um só bloco: primeira linha forte (aparece na busca), depois contexto',
      'linkedin' => 'tom profissional, pode ser mais longo, foco em insight/valor, sem gírias',
      'x' => 'extremamente curto (cabe em ~280 caracteres), direto ao ponto, no máx. 1-2 hashtags',
      'threads' => 'tom casual e conversacional, curto, como um comentário espontâneo'
    }.freeze
    DEFAULT_CAPTION_RULE = 'legenda final pronta para publicar: gancho na 1ª linha, corpo curto e CTA'

    def self.fillable_keys(status)
      SPECS.fetch(status.to_s, {}).keys
    end

    # The Anthropic tool schema for this status — the actual JSON contract
    # (Operations::Ai::FillFields forces tool_choice to this, so the response is
    # always shaped exactly like this, never parsed out of free text).
    def self.tool(status, channels: [])
      fields = SPECS.fetch(status.to_s, {})
      properties = fields.each_with_object({}) do |(key, desc), acc|
        acc[key] = key == 'captions' ? captions_schema(channels) : field_schema(key, desc)
      end

      {
        'name' => TOOL_NAME,
        'description' => "Preenche os campos de conteúdo da etapa \"#{status}\" de um ticket de agência.",
        'input_schema' => { 'type' => 'object', 'required' => fields.keys, 'properties' => properties }
      }
    end

    def self.field_schema(key, desc)
      return { 'type' => 'array', 'items' => { 'type' => 'string' }, 'description' => desc } if ARRAY_FIELDS.include?(key)
      return { 'type' => 'string', 'enum' => %w[repeat iterate retire], 'description' => desc } if key == 'repeat_recommendation'

      { 'type' => 'string', 'description' => desc }
    end

    # One required string property per connected channel, each carrying that
    # network's own writing rules — this is what makes every caption arrive
    # already optimized per platform instead of one generic string reused
    # everywhere.
    def self.captions_schema(channels)
      list = Array(channels).presence || %w[instagram]
      properties = list.each_with_object({}) do |channel, acc|
        rule = NETWORK_CAPTION_RULES.fetch(channel.to_s, DEFAULT_CAPTION_RULE)
        acc[channel.to_s] = { 'type' => 'string', 'description' => "Legenda para #{channel}: #{rule}" }
      end
      {
        'type' => 'object',
        'description' => 'Uma chave por canal conectado, cada valor já pronto para publicar naquele canal.',
        'required' => list.map(&:to_s),
        'properties' => properties
      }
    end

    def system
      fields = SPECS.fetch(context[:status].to_s, {})
      task_lines = fields.map { |key, desc| "- #{key}: #{desc}" }.join("\n")

      <<~SYS
        Você é um(a) estrategista de conteúdo sênior de uma agência de social media.
        #{brand_block}
        #{positioning_block}
        Sua tarefa: preencher, via a ferramenta #{TOOL_NAME}, os campos da etapa
        "#{context[:status_label]}" deste ticket, usando TODO o contexto já produzido
        nas etapas anteriores (fornecido a seguir). Seja específico, acionável e
        coerente com a marca e o posicionamento acima. Não invente métricas que não
        existam no contexto.

        Campos a preencher:
        #{task_lines}

        Português do Brasil.
      SYS
    end

    def user_prompt
      context[:ctx].to_s
    end
  end
end
