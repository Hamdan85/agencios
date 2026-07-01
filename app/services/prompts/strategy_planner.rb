# frozen_string_literal: true

module Prompts
  # The conversational content-strategy planner — a social-media SENIOR that runs
  # a multi-turn chat to turn a monthly cadence brief ("1 reel/semana, 2
  # carrosséis/semana…") into a concrete, scheduled content plan.
  #
  # It does NOT dump a plan on turn one: it asks one gap at a time (channels,
  # window, cadence, posting days, pillars, team capacity, approval) and only
  # calls the `propose_content_plan` tool once the strategy is feasible and good.
  # Questions stream as plain text; the final plan arrives as a structured tool
  # call captured by Vendors::Anthropic::Client (→ StrategySession#proposed_plan).
  class StrategyPlanner < Base
    TOOL_NAME = 'propose_content_plan'
    UPDATE_PROJECT_TOOL = 'update_project'

    CREATIVE_TYPES = %w[reel carousel feed_image story ugc_video ad thumbnail].freeze
    CHANNELS = Ticket::CHANNELS
    PRIORITIES = %w[low medium high].freeze
    PROJECT_STATUSES = %w[active paused archived completed].freeze

    # The tools the planner can call: propose the content plan, and update the
    # project's own metadata (name, description, dates, status).
    def self.tools
      [tool, update_project_tool]
    end

    # Anthropic tool schema for the final structured plan. Kept here next to the
    # prompt so the contract and the instructions evolve together.
    def self.tool
      {
        'name' => TOOL_NAME,
        'description' => 'Propõe o plano de conteúdo final: os tickets a criar, cada um ' \
                         'com data de postagem e uma checklist de produção estimada e ' \
                         'retro-agendada. Chame SOMENTE quando a estratégia estiver ' \
                         'completa, factível e validada com o usuário.',
        'input_schema' => {
          'type' => 'object',
          'required' => %w[summary tickets],
          'properties' => {
            'summary' => {
              'type' => 'string',
              'description' => 'Resumo curto da estratégia (cadência, janela, foco).'
            },
            'tickets' => {
              'type' => 'array',
              'description' => 'Um item por peça de conteúdo a produzir na janela. Definem a ' \
                               'estratégia: tipo de criativo, canais, data de postagem e o ' \
                               'conteúdo de ideação de cada peça.',
              'items' => {
                'type' => 'object',
                'required' => %w[title creative_type channels scheduled_at brief objective
                                 target_persona content_pillar format_hypothesis subtasks],
                'properties' => {
                  'title' => { 'type' => 'string' },
                  'creative_type' => {
                    'type' => 'string', 'enum' => CREATIVE_TYPES,
                    'description' => 'Formato da peça (delimita a estratégia).'
                  },
                  'channels' => {
                    'type' => 'array',
                    'items' => { 'type' => 'string', 'enum' => CHANNELS },
                    'description' => 'Redes onde a peça será postada.'
                  },
                  'priority' => { 'type' => 'string', 'enum' => PRIORITIES },
                  'scheduled_at' => {
                    'type' => 'string',
                    'description' => 'Data/hora prevista de postagem, ISO 8601.'
                  },
                  'brief' => {
                    'type' => 'string',
                    'description' => 'Briefing de ideação: contexto e direção da peça (2-3 frases).'
                  },
                  'objective' => {
                    'type' => 'string',
                    'description' => 'Objetivo do conteúdo em uma frase.'
                  },
                  'target_persona' => {
                    'type' => 'string',
                    'description' => 'Persona-alvo específica desta peça, em uma frase.'
                  },
                  'content_pillar' => {
                    'type' => 'string',
                    'description' => 'Pilar de conteúdo (ex.: educacional, bastidores, prova social).'
                  },
                  'format_hypothesis' => {
                    'type' => 'string',
                    'description' => 'Hipótese de formato (ex.: Reel narrativo de 30s).'
                  },
                  'subtasks' => {
                    'type' => 'array',
                    'description' => 'Checklist de produção, retro-agendada a partir do post.',
                    'items' => {
                      'type' => 'object',
                      'required' => %w[title estimate_hours lead_offset_days],
                      'properties' => {
                        'title' => { 'type' => 'string' },
                        'estimate_hours' => {
                          'type' => 'number',
                          'description' => 'Esforço estimado em horas.'
                        },
                        'lead_offset_days' => {
                          'type' => 'integer',
                          'description' => 'Dias ANTES da postagem em que a tarefa deve estar pronta.'
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    end

    # Lets the agent update the project's own metadata as part of planning (e.g.
    # set realistic start/end dates, sharpen the name/description, change status).
    def self.update_project_tool
      {
        'name' => UPDATE_PROJECT_TOOL,
        'description' => 'Atualiza os dados do PRÓPRIO projeto (não os tickets): nome, ' \
                         'descrição, datas de início/fim e status. Use quando fizer sentido ' \
                         'ajustar o projeto — ex.: definir a janela real da campanha.',
        'input_schema' => {
          'type' => 'object',
          'properties' => {
            'name' => { 'type' => 'string' },
            'description' => { 'type' => 'string' },
            'starts_on' => { 'type' => 'string', 'description' => 'Data ISO (YYYY-MM-DD) ou vazio.' },
            'ends_on' => { 'type' => 'string', 'description' => 'Data ISO (YYYY-MM-DD) ou vazio.' },
            'status' => { 'type' => 'string', 'enum' => PROJECT_STATUSES }
          }
        }
      }
    end

    def system
      <<~SYS
        Você é o parceiro de conteúdo do time desta agência, conduzindo o planejamento
        de um projeto. Data de hoje: #{Date.current.iso8601}. Tenha a competência de um
        social media sênior, mas fale como um colega: amigável, direto e proativo. NUNCA
        se descreva como "sênior" nem diga coisas como "como estrategista sênior" — apenas
        aja bem. Sem jargão pomposo; converse de forma natural e prática.

        Você JÁ TEM o contexto completo do cliente abaixo — marca, voz, posicionamento
        e redes conectadas. Use-o para preencher as lacunas por conta própria; NÃO
        pergunte o que já está aqui.
        #{brand_block}
        #{connected_channels_block}
        #{positioning_block}

        Objetivo: transformar a intenção do usuário (ex.: "1 reel por semana, 2
        carrosséis por semana, 2 posts por semana") em um plano de conteúdo concreto,
        com datas de postagem e uma checklist de produção estimada para cada peça.

        Postura — seja PROATIVO, não um questionário:
        - Assim que tiver o MÍNIMO necessário (o período — um mês, uma campanha ou
          contínuo — e a cadência por formato), PROPONHA o plano chamando a ferramenta.
          O projeto NÃO é necessariamente mensal e pode não ter datas de início/fim;
          se o período não for dado, assuma as próximas ~4 semanas a partir de hoje.
          Não peça confirmação para propor — o usuário revisa e aprova o plano na tela.
        - Preencha o resto sozinho a partir do contexto do cliente e de boas práticas:
          use as redes CONECTADAS do cliente como canais padrão; escolha dias/horários
          de bom desempenho (ex.: ter/qua/qui, manhã/começo da noite); derive os temas
          dos pilares de conteúdo e do posicionamento; estime esforço e antecedência.
        - Faça no MÁXIMO 1–2 perguntas, e só se forem realmente essenciais e ausentes
          (tipicamente a janela ou a cadência). Se o usuário já deu ambas, proponha JÁ.
        - Se algo estiver fraco ou inviável, ajuste no plano e explique brevemente —
          não trave a conversa com perguntas.
        - PRAZOS REALISTAS: some o lead time da checklist (a maior antecedência) de cada
          peça. A primeira postagem NUNCA pode exigir tarefas no passado. Se o pedido
          for apertado demais (ex.: "poste amanhã" mas a produção leva 5 dias), CRITIQUE
          e proponha datas realistas — empurre a primeira postagem para dar tempo de
          produzir com qualidade. Nunca gere tarefas com prazo anterior a hoje.
        - Ao propor: escreva ANTES UMA frase curta avisando (ex.: "Fechado, montando o
          plano — dá uma olhada nos tickets à esquerda.") e SÓ ENTÃO chame a ferramenta
          #{TOOL_NAME}. Não redescreva o plano em texto — os tickets aparecem na lista.
        - Você também pode ajustar o PRÓPRIO projeto com a ferramenta #{UPDATE_PROJECT_TOOL}
          (nome, descrição, datas de início/fim, status) — ex.: definir a janela real da
          campanha que vocês acabaram de combinar. Pode chamá-la junto com o plano.

        Regras do plano:
        - O ticket nasce em IDEAÇÃO, mas o plano DELIMITA a estratégia: defina
          `creative_type` (formato) e `channels` (redes) de cada peça — são o que
          torna a cadência concreta ("1 reel no Instagram", "2 carrosséis"…).
        - Distribua os tickets ao longo da janela conforme a cadência; defina
          `scheduled_at` (data/hora de postagem) coerente com bons horários e com lead
          time suficiente (a primeira peça precisa de dias de produção ANTES de postar).
        - Canais padrão = redes conectadas do cliente (a menos que o usuário peça outras).
        - Preencha SEMPRE todos os campos de ideação de cada ticket: `brief`, `objective`,
          `target_persona`, `content_pillar` e `format_hypothesis` — específicos por peça,
          coerentes com a marca e o posicionamento. Não deixe nenhum em branco.
        - `creative_type` deve ser um de: #{CREATIVE_TYPES.join(', ')}.
        - `channels` devem ser um subconjunto de: #{CHANNELS.join(', ')}.
        - Cada ticket tem uma checklist ENXUTA de 3 a 4 subtarefas com `estimate_hours`
          (esforço) e `lead_offset_days` (dias de antecedência), garantindo que o post
          fique pronto antes de `scheduled_at`. Não passe de 4 subtarefas por ticket.

        Responda sempre em português do Brasil, de forma direta e profissional.
      SYS
    end

    private

    # The client's actually-connected networks — the sensible default channel set
    # for the plan (the agency connects each client's Instagram/TikTok/etc.).
    def connected_channels_block
      providers = client&.social_accounts&.pluck(:provider)&.uniq
      return 'Redes conectadas do cliente: nenhuma conectada ainda.' if providers.blank?

      "Redes conectadas do cliente (use como canais padrão do plano): #{providers.join(', ')}"
    end
  end
end
