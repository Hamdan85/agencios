# frozen_string_literal: true

module Prompts
  # AI extraction from a landing page: given the distilled content of a brand's
  # site (metadata, links, contact info, visible copy), the model EXTRACTS and
  # ORGANIZES the brand into a full client draft — contact, brand identity, and
  # structured positioning — in a single JSON object the operation parses.
  class ClientFromLandingPage < Base
    def system
      <<~SYS
        Você é estrategista de marca de uma agência de social media.
        #{brand_block}
        Você recebeu o conteúdo extraído da landing page / site de uma marca
        (metadados, links, contatos e texto visível). EXTRAIA e ORGANIZE as
        informações para cadastrar este cliente. Use apenas o que estiver
        presente ou for razoavelmente inferível do conteúdo; NÃO invente fatos
        (e-mail, telefone, documento). Se um campo não aparecer, devolva string
        vazia (ou lista vazia em content_pillars).

        Responda APENAS com um objeto JSON válido (sem markdown, sem comentários),
        com EXATAMENTE esta estrutura:
        {
          "contact": {
            "name": "nome da marca/empresa (usado como nome do cliente)",
            "company": "razão social / nome da empresa, se diferente",
            "email": "e-mail de contato, se houver",
            "phone": "telefone de contato, se houver"
          },
          "brand": {
            "brand_voice": "tom e personalidade percebidos no texto",
            "default_handle": "@ do Instagram (somente o nome, sem @), se houver",
            "brand_primary_color": "cor primária da marca em hex #RRGGBB, se inferível",
            "brand_secondary_color": "cor secundária da marca em hex #RRGGBB, se inferível"
          },
          "positioning": {
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
        }
        Use português do Brasil.
      SYS
    end

    def user_prompt
      d = context[:digest] || {}
      socials = (d[:socials] || {}).map { |network, link| "#{network}: #{link}" }.join("\n").presence || "—"

      <<~TXT
        URL: #{d[:url]}
        Título: #{d[:title].presence || "—"}
        Descrição: #{d[:description].presence || "—"}
        Nome do site: #{d[:site_name].presence || "—"}
        Cor do tema (meta): #{d[:theme_color].presence || "—"}
        E-mails encontrados: #{Array(d[:emails]).join(", ").presence || "—"}
        Telefones encontrados: #{Array(d[:phones]).join(", ").presence || "—"}
        Redes sociais encontradas:
        #{socials}

        Texto visível da página:
        #{d[:text].presence || "—"}
      TXT
    end
  end
end
