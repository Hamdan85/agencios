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
    ACTION_TOOL = 'strategy_action'
    CARD_TOOL = 'revise_ticket'
    ADD_TOOL = 'add_tickets'
    UPDATE_PROJECT_TOOL = 'update_project'

    PROJECT_STATUSES = %w[active paused archived completed].freeze
    CREATIVE_TYPES = %w[reel carousel feed_image story ugc_video ad thumbnail].freeze
    CHANNELS = Ticket::CHANNELS
    PRIORITIES = %w[low medium high].freeze
    # A proposed ticket card carries ONLY what the approval view shows. The heavy
    # ideation brief + production checklist are generated per ticket when it's
    # created (Operations::Ai::FillFields + BuildScope), never in the plan.
    CARD_REQUIRED = %w[title creative_type channels scheduled_at].freeze

    # Tools available DURING the streamed conversation. The plan is NOT streamed
    # and — because the model emits tool calls unreliably mid-conversation — the
    # ACTION (generate / revise / wait) is not left to a spontaneous tool call
    # either: a job runs a separate forced-tool router (#action_tool) off the
    # request. The stream only keeps update_project (a nice-to-have).
    def self.stream_tools
      [update_project_tool]
    end

    # Forced-tool router (deterministic): after each turn, decide what to DO —
    # keep talking, generate the batch, or revise ONE proposed ticket the user
    # asked to change. Runs off the request (in the job), so streamed tool-call
    # flakiness never gates the action.
    def self.action_tool
      {
        'name' => ACTION_TOOL,
        'description' => 'Decide a próxima ação a partir da conversa, do plano já proposto (se ' \
                         'houver) e dos tickets que o projeto já tem: continuar conversando, ' \
                         'montar o plano inteiro, adicionar NOVOS tickets a um projeto que já ' \
                         'tem tickets, ou revisar UM ticket específico que o usuário pediu para mudar.',
        'input_schema' => {
          'type' => 'object', 'required' => %w[action],
          'properties' => {
            'action' => {
              'type' => 'string', 'enum' => %w[wait generate_plan add_tickets revise_ticket],
              'description' => 'wait = ainda conversando / falta algo; ' \
                               'generate_plan = montar o plano inteiro do zero (nenhum ticket ainda, ' \
                               'ou refazer toda a cadência); ' \
                               'add_tickets = o usuário pediu para ACRESCENTAR uma ou mais peças ' \
                               'novas a um projeto que JÁ tem tickets (ex.: "crie mais um ticket de X"), ' \
                               'sem mexer nos existentes; ' \
                               'revise_ticket = o usuário pediu para mudar um ticket já proposto.'
            },
            'ticket_key' => { 'type' => 'string', 'description' => 'Chave (key) do ticket a revisar — só em revise_ticket.' },
            'instruction' => {
              'type' => 'string',
              'description' => 'O que fazer: em revise_ticket, o que mudar naquele ticket; em ' \
                               'add_tickets, quais peças novas criar (formato, tema, quantidade).'
            }
          }
        }
      }
    end

    # Additive schema: propose ONLY the new tickets to append to a running project,
    # never repeating what already exists. Same slim card shape as the batch.
    def self.add_tool
      {
        'name' => ADD_TOOL,
        'description' => 'Acrescenta NOVOS tickets a um projeto que já tem conteúdo — apenas as ' \
                         'peças pedidas agora, sem repetir nenhum ticket existente. Cada card traz ' \
                         'formato, canais e data de postagem, como no plano.',
        'input_schema' => {
          'type' => 'object', 'required' => %w[tickets],
          'properties' => {
            'tickets' => {
              'type' => 'array',
              'description' => 'Só os tickets NOVOS a adicionar (um por peça pedida).',
              'items' => { 'type' => 'object', 'required' => CARD_REQUIRED, 'properties' => card_properties }
            }
          }
        }
      }
    end

    # The batch schema (slim): the planner only produces what the approval card
    # shows — title, format, channels, priority, posting date. Brief + checklist
    # come per ticket at creation, never here.
    def self.plan_tool
      {
        'name' => TOOL_NAME,
        'description' => 'Propõe o plano de conteúdo: os tickets a criar, cada um com formato, ' \
                         'canais e data de postagem. Chame SOMENTE quando a estratégia estiver ' \
                         'completa e factível.',
        'input_schema' => {
          'type' => 'object', 'required' => %w[summary tickets],
          'properties' => {
            'summary' => { 'type' => 'string', 'description' => 'Resumo curto da estratégia (cadência, janela, foco).' },
            'tickets' => {
              'type' => 'array',
              'description' => 'Um item por peça de conteúdo na janela — define a estratégia: ' \
                               'formato, canais e data de postagem.',
              'items' => { 'type' => 'object', 'required' => CARD_REQUIRED, 'properties' => card_properties }
            }
          }
        }
      }
    end

    # Single-card schema for revising ONE proposed ticket in place.
    def self.card_tool
      {
        'name' => CARD_TOOL,
        'description' => 'Reescreve UM ticket proposto conforme o pedido do usuário, mantendo o ' \
                         'formato de card (título, formato, canais, prioridade, data).',
        'input_schema' => { 'type' => 'object', 'required' => CARD_REQUIRED, 'properties' => card_properties }
      }
    end

    def self.tool = plan_tool

    # The approval-visible fields of one ticket card — shared by plan_tool (array)
    # and card_tool (single, for revision).
    def self.card_properties
      {
        'title' => { 'type' => 'string' },
        'creative_type' => { 'type' => 'string', 'enum' => CREATIVE_TYPES, 'description' => 'Formato da peça (delimita a estratégia).' },
        'channels' => {
          'type' => 'array', 'items' => { 'type' => 'string', 'enum' => CHANNELS },
          'description' => 'Redes onde a peça será postada.'
        },
        'priority' => { 'type' => 'string', 'enum' => PRIORITIES },
        'scheduled_at' => {
          'type' => 'string',
          'description' => 'Data/hora prevista de postagem, ISO 8601. Dentro do próximo mês ' \
                           "(no máximo #{1.month.from_now.to_date.iso8601}); nunca além."
        }
      }
    end

    # Lets the agent update the project's own metadata as part of planning (e.g.
    # set realistic start/end dates, sharpen the name/description, change status).
    def self.update_project_tool
      {
        'name' => UPDATE_PROJECT_TOOL,
        'description' => 'Atualiza os dados do PRÓPRIO projeto (não os tickets): nome, ' \
                         'descrição, datas de início/fim e status. Use para ajustar o projeto — ' \
                         'ex.: definir a janela real da campanha. REGRA DO STATUS: só inicie o ' \
                         'projeto (status → active, tirando do rascunho) se o usuário pedir ' \
                         'explicitamente para INICIAR/COMEÇAR; nunca inicie por conta própria.',
        'input_schema' => {
          'type' => 'object',
          'properties' => {
            'name' => { 'type' => 'string' },
            'description' => { 'type' => 'string' },
            'starts_on' => { 'type' => 'string', 'description' => 'Data ISO (YYYY-MM-DD) ou vazio.' },
            'ends_on' => { 'type' => 'string', 'description' => 'Data ISO (YYYY-MM-DD) ou vazio.' },
            'status' => {
              'type' => 'string', 'enum' => PROJECT_STATUSES,
              'description' => 'Só mude para `active` (iniciar) se o usuário pedir explicitamente ' \
                               'para iniciar/começar o projeto. Caso contrário, NÃO envie status.'
            }
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

        OS DOIS MODOS DO PROJETO (entenda bem e explique ao usuário quando fizer sentido):
        - RASCUNHO (planejamento) — o modo padrão enquanto vocês conversam. Você planeja,
          propõe e revisa o plano; o projeto fica em RASCUNHO e NADA é produzido ou
          publicado. Aprovar o plano cria os tickets, mas o projeto CONTINUA em rascunho.
        - GO (ativo) — quando o usuário INICIA (dizendo "iniciar/começar" ou clicando no
          botão GO), o projeto vira ATIVO e os tickets entram em execução no piloto
          automático: geram os criativos e agendam/publicam sozinhos. Iniciar é decisão
          do usuário — NUNCA inicie por conta própria; na dúvida, mantenha em rascunho.

        Postura — seja PROATIVO, não um questionário:
        - Assim que tiver o MÍNIMO necessário (o período — um mês, uma campanha ou
          contínuo — e a cadência por formato), PROPONHA o plano chamando a ferramenta.
          O projeto NÃO é necessariamente mensal e pode não ter datas de início/fim;
          se o período não for dado, assuma as próximas ~4 semanas a partir de hoje.
          Não peça confirmação para propor — o usuário revisa e aprova o plano na tela.
        - LIMITE RÍGIDO: você só pode planejar conteúdo para NO MÁXIMO UM MÊS a
          partir de hoje (#{Date.current.iso8601}). Nenhuma peça pode ter
          `scheduled_at` além de #{1.month.from_now.to_date.iso8601}. Se o usuário
          pedir uma janela maior (ex.: "os próximos 3 meses"), planeje apenas este
          primeiro mês, avise que cobriu o primeiro mês e sugira montar o restante
          depois — não estenda as datas além do limite.
        - Preencha o resto sozinho a partir do contexto do cliente e de boas práticas:
          use as redes CONECTADAS do cliente como canais padrão; escolha dias/horários
          de bom desempenho (ex.: ter/qua/qui, manhã/começo da noite); derive os temas
          dos pilares de conteúdo e do posicionamento; estime esforço e antecedência.
        - Faça no MÁXIMO 1–2 perguntas, e só se forem realmente essenciais e ausentes
          (tipicamente a janela ou a cadência). Se o usuário já deu ambas, proponha JÁ.
        - Se algo estiver fraco ou inviável, ajuste no plano e explique brevemente —
          não trave a conversa com perguntas.
        - ADICIONAR peças a um projeto que JÁ tem tickets: quando o usuário pedir
          "crie mais um ticket de X", "adiciona um post de Y" etc., NÃO refaça o
          plano inteiro — proponha só as peças NOVAS, que aparecem como rascunho
          esmaecido ao lado dos tickets existentes para o usuário aprovar. Nunca
          repita nem recrie os tickets que já existem.
        - PRAZOS REALISTAS: reserve alguns dias de produção antes da primeira postagem.
          Se o pedido for apertado demais (ex.: "poste amanhã" mas a produção leva
          dias), CRITIQUE e proponha datas realistas — empurre a primeira postagem para
          dar tempo de produzir com qualidade.
        - Quando a estratégia estiver pronta, escreva UMA frase curta avisando que vai
          montar (ex.: "Fechado, vou montar o plano — dá uma olhada nos tickets à esquerda.").
          Os tickets são gerados automaticamente e aparecem na lista — NÃO os descreva em texto.
        - Você também pode ajustar o PRÓPRIO projeto com a ferramenta #{UPDATE_PROJECT_TOOL}
          (nome, descrição, datas de início/fim) — ex.: definir a janela real da campanha
          que vocês acabaram de combinar. Pode chamá-la junto com o plano. Só envie
          `status: active` para INICIAR se o usuário pedir explicitamente (ver "OS DOIS
          MODOS" acima); planejar/propor/revisar mantém o projeto em rascunho.

        Regras do plano:
        - O ticket nasce em IDEAÇÃO, mas o plano DELIMITA a estratégia: defina
          `creative_type` (formato) e `channels` (redes) de cada peça — é o que
          torna a cadência concreta ("1 reel no Instagram", "2 carrosséis"…).
        - Distribua os tickets ao longo da janela conforme a cadência; defina
          `scheduled_at` (data/hora de postagem) coerente com bons horários e com
          dias de produção suficientes antes de postar.
        - Canais padrão = redes conectadas do cliente (a menos que o usuário peça outras).
        - `creative_type` deve ser um de: #{CREATIVE_TYPES.join(', ')}.
        - `channels` devem ser um subconjunto de: #{CHANNELS.join(', ')}.
        - NÃO escreva brief, roteiro nem checklist aqui. O briefing de ideação e as
          subtarefas de produção de cada ticket são gerados automaticamente QUANDO o
          ticket é criado — o plano é só o esqueleto: título, formato, canais,
          prioridade e data.

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
