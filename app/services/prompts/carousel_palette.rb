# frozen_string_literal: true

module Prompts
  # Vision prompt: given a client's carousel BACKGROUND IMAGE (attached as an image
  # the model sees) plus the brand context, decide the carousel's own color palette
  # — the accent/text/scrim used ONLY by the `image` carousel style. This is an
  # aesthetic judgment (what pops against THIS photo, stays legible, and harmonizes
  # with — but does not merely copy — the brand), which is why it's a vision model
  # call, not pixel sampling.
  #
  # The output is a forced tool call (AiAdapter#complete_tool reads the structured
  # tool_input — never freeform text). The derived palette is stored separately from
  # the brand color columns; gradient/white carousels keep using the brand colors.
  class CarouselPalette < Base
    TOOL_NAME = 'set_carousel_palette'

    HEX = '^#[0-9A-Fa-f]{6}$'

    # Legibility levers, cheapest first: a shadow leaves the photo intact, a scrim
    # dims it. The model must exhaust the former before reaching for the latter.
    TEXT_SHADOWS = %w[none soft strong].freeze

    # The forced tool schema — the exact JSON contract the model must return.
    TOOL = {
      'name' => TOOL_NAME,
      'description' => 'Define a paleta de cores do carrossel derivada da imagem de fundo do cliente, ' \
                       'ancorada na identidade visual da marca.',
      'input_schema' => {
        'type' => 'object',
        'required' => %w[accent on_accent text_color scrim_color scrim_opacity text_shadow],
        'properties' => {
          'accent' => {
            'type' => 'string', 'pattern' => HEX,
            'description' => 'Cor de destaque (kicker, sublinhado do "arraste", chip de iniciais do avatar). ' \
                             'PARTA DAS CORES DA MARCA: use a primária ou a secundária sempre que ela se ' \
                             'sustentar sobre esta foto. Só afaste-se quando o contraste for ruim — e, nesse ' \
                             'caso, escolha um tom da MESMA FAMÍLIA DE MATIZ (mesma cor, saturação/brilho ' \
                             'ajustados), para o carrossel continuar reconhecível como sendo desta marca.'
          },
          'on_accent' => {
            'type' => 'string', 'pattern' => HEX,
            'description' => 'Cor do texto/iniciais SOBRE o chip accent. Deve ter contraste AA (>= 4.5:1) com accent — ' \
                             'normalmente #FFFFFF ou #111111.'
          },
          'text_color' => {
            'type' => 'string', 'pattern' => HEX,
            'description' => 'Cor de headline/corpo/nome sobre a foto: claro sobre foto escura, escuro sobre foto ' \
                             'clara. Não precisa ser #FFFFFF puro — um branco (ou uma tinta escura) levemente ' \
                             'tingido com o matiz da marca integra melhor o texto à identidade.'
          },
          'scrim_color' => {
            'type' => 'string', 'pattern' => HEX,
            'description' => 'Cor da camada sobre a foto (só aplicada se scrim_opacity > 0). NÃO use #000000 puro ' \
                             'por reflexo: prefira um tom bem escuro (ou bem claro, se o texto for escuro) TINGIDO ' \
                             'com o matiz da marca — escurece sem lavar a foto e preserva a identidade.'
          },
          'scrim_opacity' => {
            'type' => 'number', 'minimum' => 0, 'maximum' => 0.6,
            'description' => 'ÚLTIMO recurso. 0 = foto limpa, e é o padrão preferido. Só passe de 0 (0.1–0.5) se, ' \
                             'MESMO com text_shadow = "strong", o texto continuar ilegível — foto muito clara, ' \
                             'poluída ou de baixo contraste.'
          },
          'text_shadow' => {
            'type' => 'string', 'enum' => TEXT_SHADOWS,
            'description' => 'PRIMEIRO recurso de legibilidade: sombra atrás do texto, que preserva a foto intacta. ' \
                             '"none" = foto escura e limpa, o texto já se lê sozinho. "soft" = padrão seguro. ' \
                             '"strong" = foto clara/poluída — tente ISTO antes de recorrer ao scrim.'
          },
          'reasoning' => {
            'type' => 'string',
            'description' => 'Justificativa curta (1 frase) da escolha — para auditoria.'
          }
        }
      }
    }.freeze

    def system
      <<~SYS
        Você é um(a) diretor(a) de arte especializado(a) em identidade visual para redes sociais.
        #{brand_block}

        Você recebe a IMAGEM DE FUNDO que será usada em TODOS os slides de um carrossel deste cliente.
        Sua tarefa: definir, via a ferramenta #{TOOL_NAME}, a paleta de cores do carrossel para ESTA imagem.

        Diretrizes:
        - A MARCA é o ponto de partida; a FOTO é a restrição. O accent deve sair das cores da marca
          (acima) sempre que elas se sustentarem sobre esta imagem. Quando não se sustentarem, ajuste
          DENTRO DA MESMA FAMÍLIA DE MATIZ (mesma cor, saturação/brilho recalibrados) em vez de trocar
          por uma cor alheia — o carrossel precisa continuar reconhecível como sendo desta marca.
        - LEGIBILIDADE em camadas, da mais barata para a mais cara. A foto é o ativo: preserve-a.
          1. text_color adequado ao brilho da foto (claro sobre escura, escuro sobre clara);
          2. text_shadow — "soft" e, se preciso, "strong": a foto continua intacta;
          3. scrim (scrim_opacity > 0) SOMENTE quando 1 + 2 não bastarem.
          Escurecer a foto por reflexo é falha de direção de arte, não solução.
        - Se o scrim for mesmo necessário, tinja-o com o matiz da marca em vez de usar preto puro.
        - on_accent precisa contrastar com accent (texto legível sobre o chip de destaque).
        - Todas as cores em hexadecimal #RRGGBB.

        Responda SOMENTE chamando a ferramenta.
      SYS
    end

    def user_prompt
      'Analise a imagem de fundo anexada e defina a paleta do carrossel para ela.'
    end
  end
end
