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

    # The forced tool schema — the exact JSON contract the model must return.
    TOOL = {
      'name' => TOOL_NAME,
      'description' => 'Define a paleta de cores do carrossel derivada da imagem de fundo do cliente.',
      'input_schema' => {
        'type' => 'object',
        'required' => %w[accent on_accent text_color scrim_color scrim_opacity],
        'properties' => {
          'accent' => {
            'type' => 'string', 'pattern' => HEX,
            'description' => 'Cor de destaque (kicker, sublinhado do "arraste", chip de iniciais do avatar). ' \
                             'DEVE contrastar e harmonizar com a FOTO — não precisa copiar as cores da marca. ' \
                             'Escolha um tom vibrante presente ou complementar à imagem.'
          },
          'on_accent' => {
            'type' => 'string', 'pattern' => HEX,
            'description' => 'Cor do texto/iniciais SOBRE o chip accent. Deve ter contraste AA (>= 4.5:1) com accent — ' \
                             'normalmente #FFFFFF ou #111111.'
          },
          'text_color' => {
            'type' => 'string', 'pattern' => HEX,
            'description' => 'Cor de headline/corpo/nome sobre a foto. Normalmente #FFFFFF; use uma tinta escura ' \
                             '(ex.: #111111) apenas se a foto for predominantemente clara.'
          },
          'scrim_color' => {
            'type' => 'string', 'pattern' => HEX,
            'description' => 'Cor da camada de escurecimento/clareamento sobre a foto (só aplicada se scrim_opacity > 0).'
          },
          'scrim_opacity' => {
            'type' => 'number', 'minimum' => 0, 'maximum' => 0.6,
            'description' => '0 = foto totalmente limpa (padrão atual). Aumente (0.1–0.5) somente quando a foto for ' \
                             'clara/poluída e o texto ficaria ilegível sem escurecer o fundo.'
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
        - As cores devem nascer da FOTO — escolha um accent que se destaque sobre ela e a valorize.
          NÃO é para copiar as cores da marca; a marca é apenas contexto de tom. Este carrossel de
          imagem de fundo tem cores próprias, diferentes do fundo gradiente/branco (que usam a marca).
        - Garanta LEGIBILIDADE do texto branco (ou escuro) sobre a foto. Se a imagem for clara,
          poluída ou de baixo contraste, defina um scrim (scrim_opacity > 0) para escurecê-la o
          suficiente; se a foto já for escura e limpa, mantenha scrim_opacity = 0.
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
