# frozen_string_literal: true

module Prompts
  # Status-aware "fill the current phase's fields" prompt. Given everything the
  # team has already produced in the earlier funnel stages (carried in via
  # `ctx`), Claude returns a JSON object whose keys are exactly the fillable
  # fields of the ticket's current status. Drives the per-phase "Gerar com IA"
  # action (Operations::Ai::FillFields).
  #
  # Only *content* fields are AI-fillable — human decisions (dates, switches,
  # approval status, the channel selection) are intentionally excluded.
  class FieldFill < Base
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
        'deliverables' => 'Lista de entregáveis concretos (array de strings)',
        'effort_estimate' => 'Estimativa de esforço (ex.: 4h, 2 dias)'
      },
      'production' => {
        'caption' => 'Legenda final pronta para publicar: gancho na 1ª linha, corpo curto e CTA',
        'hashtags' => 'Hashtags relevantes SEM o # (array de 5 a 12 strings)',
        'internal_notes' => 'Observações de produção para a equipe (HTML simples)'
      },
      'scheduled' => {
        'first_comment' => 'Primeiro comentário a fixar no post (hashtags extras / contexto)'
      },
      'retrospective' => {
        'wins' => 'O que funcionou bem (array de strings)',
        'improvements' => 'O que pode melhorar no próximo ciclo (array de strings)',
        'lessons_learned' => 'Aprendizado consolidado em HTML simples (<p>, <ul>, <li>, <strong>)',
        'repeat_recommendation' => 'Recomendação — exatamente um de: repeat, iterate, retire'
      }
    }.freeze

    def self.fillable_keys(status)
      SPECS.fetch(status.to_s, {}).keys
    end

    def system
      fields = SPECS.fetch(context[:status].to_s, {})
      schema = fields.map { |key, desc| %(  "#{key}": <#{desc}>) }.join("\n")

      <<~SYS
        Você é um(a) estrategista de conteúdo sênior de uma agência de social media.
        #{brand_block}
        #{positioning_block}
        Sua tarefa: preencher os campos da etapa "#{context[:status_label]}" deste ticket,
        usando TODO o contexto já produzido nas etapas anteriores (fornecido a seguir).
        Seja específico, acionável e coerente com a marca e o posicionamento acima.

        Responda SOMENTE com um objeto JSON válido (sem markdown, sem comentários,
        sem texto fora do JSON), exatamente com estas chaves:
        {
        #{schema}
        }

        Regras: campos do tipo array devem ser listas JSON de strings; campos HTML usam
        apenas tags simples (<p>, <ul>, <li>, <strong>, <em>); não invente métricas que
        não existam no contexto. Português do Brasil.
      SYS
    end

    def user_prompt
      context[:ctx].to_s
    end
  end
end
