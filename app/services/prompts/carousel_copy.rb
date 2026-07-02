# frozen_string_literal: true

module Prompts
  # Writes the per-slide copy for a viral carousel as structured JSON, so the
  # generator can lay each slide out as a branded HTML→PNG (not an AI raster).
  #
  # The carousel is ALWAYS about the brand (its positioning / value proposition),
  # serving the chosen objective. A link is only a creative HOOK — its subject is
  # connected to the brand; its title/text/facts are never reproduced.
  #
  # `slides` may be a number (honor it) or nil/"auto" (let the model choose 3–10).
  class CarouselCopy < Base
    OBJECTIVES = {
      'engagement' => 'gerar engajamento (salvamentos, comentários, compartilhamentos)',
      'reach' => 'ampliar alcance',
      'conversion' => 'gerar conversão (levar à ação/compra)',
      'education' => 'educar a audiência'
    }.freeze

    def system
      <<~SYS
        Você é especialista em carrosséis virais para redes sociais.
        #{brand_block}
        #{positioning_block}

        REGRA CENTRAL: o carrossel é SEMPRE sobre a marca acima — sua proposta de
        valor, seus diferenciais e como ela ajuda o público dela. Sirva ao
        objetivo: #{objective_label}. Fale com o público da marca, na voz da marca.

        #{structure_instruction}
        Texto curto, escaneável e impactante; respeite a voz da marca.

        Responda SOMENTE com um array JSON válido #{count_phrase}, sem markdown e
        sem texto fora do JSON, nesta forma:
        [
          {"role":"hook|value|cta",
           "headline":"<título curto, até 60 caracteres>",
           "body":"<1 a 2 frases curtas>",
           "image":<true|false>,
           "image_query":"<2 a 4 palavras EM INGLÊS para banco de imagens, ou \\"\\">"}
        ]
        POR PADRÃO os slides são tipográficos: "image": false e "image_query": "".
        Use "image": true apenas em casos excepcionais, quando uma foto for
        essencial (ex.: mostrar um produto físico). O texto é em português do Brasil.
      SYS
    end

    def user_prompt
      [
        link_instruction,
        reference_instruction,
        present_line('Tema', context[:topic]),
        present_line('Material de apoio', context[:copy_brief]),
        present_line('Escopo de produção', context[:production_scope]),
        present_line('Roteiro', context[:script]),
        present_line('Canais', context[:channels])
      ].compact.join("\n\n").presence || 'Crie um carrossel sobre a marca e sua proposta de valor.'
    end

    private

    # References the team attached (ideation). UNLIKE the news-hook link, these are
    # supporting material to actually READ and USE for context, data and direction
    # — still expressed in the brand's voice and serving the brand's positioning.
    def reference_instruction
      urls = Array(context[:reference_urls]).map { |u| u.to_s.strip }.reject(&:blank?).uniq
      return nil if urls.empty?

      <<~TXT.strip
        REFERÊNCIAS DE APOIO — leia estes links e use como base de contexto,
        dados e direção para o conteúdo (eles foram fornecidos pela equipe):
        #{urls.map { |u| "- #{u}" }.join("\n")}
        Extraia o que for útil (ângulos, fatos, exemplos) e incorpore ao carrossel
        SOBRE A MARCA, mantendo a voz e o posicionamento da marca.
      TXT
    end

    # The link is a HOOK ONLY — never reproduced. Read it for the current-topic
    # angle, then pivot entirely to the brand.
    def link_instruction
      url = context[:link_url]
      return nil if url.to_s.strip.blank?

      <<~TXT.strip
        GANCHO DE ATUALIDADE — leia este link APENAS para entender o assunto em alta: #{url}
        É TERMINANTEMENTE PROIBIDO copiar ou parafrasear o título, frases, fatos,
        números ou qualquer conteúdo do link. NÃO resuma a notícia. NÃO escreva
        sobre o tema do link em si.
        Em vez disso, use o assunto como GANCHO criativo para um carrossel SOBRE A
        MARCA: conecte o tema do momento ao posicionamento e à proposta de valor da
        marca (como ela ajuda o público dela), servindo ao objetivo. O conteúdo é
        sobre a MARCA — o link é só a isca de relevância.
      TXT
    end

    # A numeric request is honored; nil/"auto" lets the model decide.
    def fixed_count
      raw = context[:slides]
      return nil if raw.nil? || raw.to_s.strip.downcase.in?(['', 'auto'])

      raw.to_i.clamp(3, 10)
    end

    def structure_instruction
      if fixed_count
        "Crie o conteúdo de um carrossel de #{fixed_count} slides: o slide 1 é o " \
          'GANCHO, os slides do meio entregam UM ponto cada (valor), e o último é o CTA.'
      else
        'Escolha o número ideal de slides (entre 3 e 10, normalmente 5 a 8) para a ' \
          'mensagem. O slide 1 é o GANCHO, os slides do meio entregam UM ponto cada ' \
          '(valor), e o último é o CTA.'
      end
    end

    def count_phrase
      fixed_count ? "de exatamente #{fixed_count} objetos" : 'de 3 a 10 objetos'
    end

    def objective_label
      OBJECTIVES[context[:objective].to_s] || context[:objective].presence || 'gerar engajamento'
    end

    def present_line(label, value)
      "#{label}: #{value}" if value.to_s.strip.present?
    end
  end
end
