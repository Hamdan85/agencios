# frozen_string_literal: true

module Prompts
  # AI-first positioning: the client describes the brand in free text and the
  # model FILLS the structured positioning fields (following market best
  # practices). Output is a single JSON object the operation parses.
  class ClientPositioning < Base
    # JSON keys the model must return (mirrors Client::POSITIONING_KEYS, minus
    # brand_voice which is brand identity, not positioning).
    OUTPUT_KEYS = %w[
      one_liner category mission target_audience audience_pain value_proposition
      differentiators competitors content_pillars keywords guardrails statement
    ].freeze

    def system
      <<~SYS
        Você é estrategista de marca de uma agência de social media.
        #{brand_block}
        A partir da descrição livre da marca feita pelo cliente, PREENCHA o
        posicionamento estruturado seguindo as melhores práticas de mercado:
        claro, específico e acionável. Infira o que for razoável; não invente fatos.

        Responda APENAS com um objeto JSON válido (sem markdown, sem comentários),
        com EXATAMENTE estas chaves:
        {
          "one_liner": "o que a marca faz, em uma frase",
          "category": "categoria / mercado",
          "mission": "missão / propósito",
          "target_audience": "público-alvo (ICP)",
          "audience_pain": "principal dor que resolve",
          "value_proposition": "proposta de valor única",
          "differentiators": "diferenciais frente à concorrência",
          "competitors": "concorrentes ou alternativas",
          "content_pillars": ["3 a 5 pilares de conteúdo"],
          "keywords": "palavras-chave / hashtags recorrentes",
          "guardrails": "assuntos ou abordagens a evitar",
          "statement": "um parágrafo no estilo: Para <público> que <necessidade>, <marca> é <categoria> que <benefício>, diferente de <alternativa> porque <diferencial>"
        }
        Use português do Brasil. Se um campo não puder ser inferido, devolva string vazia
        (ou lista vazia para content_pillars).
      SYS
    end

    def user_prompt
      <<~TXT
        Marca: #{context[:name].presence || '—'}
        Descrição do cliente:
        #{context[:brief].presence || '—'}
      TXT
    end
  end
end
