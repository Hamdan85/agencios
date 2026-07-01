# frozen_string_literal: true

# Server-rendered (SSR) public marketing site: Home, Como funciona,
# Funcionalidades (index + one page per feature) and Preços.
#
# These pages are intentionally NOT part of the React SPA — they are plain ERB
# rendered server-side for SEO + fast first paint, sharing the SPA's design
# system via the `marketing` Vite entrypoint. ApplicationController does not
# require authentication, so these are public.
class PagesController < ApplicationController
  layout 'marketing'
  before_action :load_catalog

  def home
    @funnel                   = FUNNEL
    @features                 = FEATURES
    @steps                    = STEPS
    @stats                    = STATS
    @networks                 = NETWORKS
    @integrations             = INTEGRATIONS
    @context_states           = CONTEXT_STATES
    @strategist               = STRATEGIST
    @plans                    = marketing_plans
    @trial_days               = Pricing.trial_days
    @annual_discount_percent  = Pricing.annual_discount_percent
    @credit_packs             = Pricing.credit_packs
    @credit_costs             = Pricing.public_catalog[:credit_costs]
  end

  def how_it_works
    @funnel = FUNNEL
    @steps  = STEPS
  end

  def features
    @features = FEATURES
  end

  def feature
    @feature = FEATURES.find { |f| f[:slug] == params[:slug] }
    return redirect_to(features_path) if @feature.nil?

    @related = FEATURES.reject { |f| f[:slug] == @feature[:slug] }.first(3)
  end

  def pricing
    @plans                   = marketing_plans
    @faqs                    = FAQS
    @trial_days              = Pricing.trial_days
    @annual_discount_percent = Pricing.annual_discount_percent
    @credit_packs            = Pricing.credit_packs
    @credit_costs            = Pricing.public_catalog[:credit_costs]
  end

  # Legal pages — the "last updated" date shown on both.
  LEGAL_UPDATED_ON = '29 de junho de 2026'

  def privacy
    @updated_on = LEGAL_UPDATED_ON
  end

  def terms
    @updated_on = LEGAL_UPDATED_ON
  end

  private

  # Available to the shared header/footer on every marketing page.
  def load_catalog
    @features_catalog = FEATURES
  end

  # Build the pricing cards from the CANONICAL plan catalog
  # (`Controllers::Billing::Plans` → the DB-backed `Pricing`, the same source the
  # real Stripe billing flow uses). Prices, seats and features come from there;
  # only the marketing presentation (tagline / highlight / CTA) is layered on
  # here, so an admin price change flows through to this page automatically.
  def marketing_plans
    Controllers::Billing::Plans.all.map do |plan|
      annual = Pricing.annual_price_cents_for(plan[:key])
      plan.merge(
        annual_price_cents: annual,
        annual_monthly_equivalent_cents: (annual / 12.0).round
      ).merge(PLAN_PRESENTATION.fetch(plan[:key], DEFAULT_PRESENTATION))
    end
  end

  DEFAULT_PRESENTATION = { tagline: nil, highlight: false, cta: 'Começar agora' }.freeze
  PLAN_PRESENTATION = {
    'solo' => { tagline: 'Para o criador ou freelancer solo.', highlight: false, cta: 'Começar agora' },
    'agencia' => { tagline: 'Para a agência em crescimento.', highlight: true, cta: 'Começar agora' },
    'enterprise' => { tagline: 'Para operações em escala.', highlight: false, cta: 'Falar com vendas' }
  }.freeze

  # ── The 7-stage production funnel (the board) ───────────────────────
  FUNNEL = [
    { key: 'ideation',      label: 'Ideação',   color: '#F59E0B', icon: 'lightbulb',
      summary: 'O brief vira ângulos.',
      desc: 'Capture o brief, o objetivo e a persona. A IA sintetiza ganchos e ideias de conteúdo prontas para escopar.' },
    { key: 'scoping',       label: 'Escopo',    color: '#0EA5E9', icon: 'ruler',
      summary: 'A ideia vira plano.',
      desc: 'Transforme a ideia escolhida num escopo concreto, com um checklist de subtarefas gerado automaticamente.' },
    { key: 'production',    label: 'Produção',  color: '#7C3AED', icon: 'wand-sparkles',
      summary: 'O plano vira criativo.',
      desc: 'Gere carrosséis, vídeos UGC e imagens com a identidade da marca — direto no estúdio, sem trocar de ferramenta.' },
    { key: 'scheduled',     label: 'Agendado',  color: '#EC4899', icon: 'calendar-clock',
      summary: 'O criativo entra na fila.',
      desc: 'Escreva legendas por rede, escolha o melhor horário e agende a publicação em cada canal.' },
    { key: 'published',     label: 'Postado',   color: '#10B981', icon: 'radio',
      summary: 'Está no ar, monitorando.',
      desc: 'Publicação multi-rede e coleta de métricas em tempo real assim que o post vai ao ar.' },
    { key: 'retrospective', label: 'Retrô',     color: '#6366F1', icon: 'chart-line',
      summary: 'O dado vira aprendizado.',
      desc: 'Uma retrospectiva automática lê as métricas e o histórico e propõe o que repetir no próximo ciclo.' },
    { key: 'done',          label: 'Concluído', color: '#14B8A6', icon: 'circle-check',
      summary: 'Arquivado com contexto.',
      desc: 'O ticket é arquivado com todo o histórico, criativos e aprendizados preservados.' }
  ].freeze

  # ── The 3-step "how it works" summary ───────────────────────────────
  STEPS = [
    { n: 1, color: '#F59E0B', icon: 'lightbulb',
      title: 'Capture a ideia',
      desc: 'Brief, objetivo e persona em segundos. A IA sintetiza ângulos e ganchos prontos para produzir.' },
    { n: 2, color: '#7C3AED', icon: 'wand-sparkles',
      title: 'Produza com IA',
      desc: 'Gere o criativo, escreva legendas por rede e aprove com o cliente — tudo no mesmo lugar.' },
    { n: 3, color: '#10B981', icon: 'send',
      title: 'Publique e meça',
      desc: 'Agende, publique em todas as redes e acompanhe as métricas em tempo real.' }
  ].freeze

  # ── Capability stats (the animated count-up band) ───────────────────
  # Honest capability metrics — what the platform does, not fabricated
  # customer numbers.
  STATS = [
    { value: 7,  suffix: '',  label: 'etapas no funil',       icon: 'workflow',    color: '#7C3AED' },
    { value: 7,  suffix: '',  label: 'redes sociais',         icon: 'share-2',     color: '#EC4899' },
    { value: 70, suffix: '+', label: 'ações via IA',          icon: 'sparkles',    color: '#F59E0B' },
    { value: 6,  suffix: '',  label: 'métricas por post',     icon: 'activity',    color: '#10B981' }
  ].freeze

  # ── Supported networks (marquee + publishing section) ───────────────
  # Direct integration for every network.
  NETWORKS = [
    { name: 'Instagram', icon: 'instagram', color: '#E1306C' },
    { name: 'Facebook',  icon: 'facebook',  color: '#1877F2' },
    { name: 'Threads',   icon: 'at-sign',   color: '#18122B' },
    { name: 'TikTok',    icon: 'music',     color: '#18122B' },
    { name: 'YouTube',   icon: 'youtube',   color: '#FF0000' },
    { name: 'LinkedIn',  icon: 'linkedin',  color: '#0A66C2' },
    { name: 'X',         icon: 'twitter-x', color: '#18122B' }
  ].freeze

  # Integrations shown in the trust marquee (product + payment + AI vendors).
  INTEGRATIONS = [
    ['Instagram', 'instagram'], ['Facebook', 'facebook'], ['Threads', 'at-sign'],
    ['TikTok', 'music'], ['YouTube', 'youtube'], ['LinkedIn', 'linkedin'],
    ['X', 'twitter-x'], ['HeyGen', 'video'],
    ['Google Meet', 'calendar-days'], ['Mercado Pago', 'receipt'], ['Stripe', 'shield-check']
  ].freeze

  # ── The contextual ticket demo (status-aware field morph) ───────────
  # Each of the 7 statuses shows its own field set + an AI summary.
  # Drives the auto-cycling mockup on the home page.
  CONTEXT_STATES = [
    { key: 'ideation', label: 'Ideação', color: '#F59E0B', icon: 'lightbulb',
      summary: 'O brief pede autoridade + prova social. Sugiro 3 ganchos de “bastidores” — o cliente responde bem a transparência.',
      fields: ['Brief', 'Objetivo', 'Persona-alvo', 'Referências'] },
    { key: 'scoping', label: 'Escopo', color: '#0EA5E9', icon: 'ruler',
      summary: 'Escopo montado: carrossel de 6 slides para Instagram + LinkedIn. Criei 5 subtarefas com estimativa de esforço.',
      fields: ['Tipo de criativo', 'Canais', 'Roteiro', 'Subtarefas', 'Prazo'] },
    { key: 'production', label: 'Produção', color: '#7C3AED', icon: 'wand-sparkles',
      summary: 'Legenda alinhada ao brief e ao tom da marca. Variação A tem o gancho mais forte para o feed.',
      fields: ['Criativo', 'Legenda', 'Hashtags', 'Aprovação'] },
    { key: 'scheduled', label: 'Agendado', color: '#EC4899', icon: 'calendar-clock',
      summary: 'Melhor janela para esta conta: ter/qui 19h. Agendei o carrossel e adaptei a legenda por rede.',
      fields: ['Horário por rede', 'Primeiro comentário', 'Link na bio'] },
    { key: 'published', label: 'No ar', color: '#10B981', icon: 'radio',
      summary: 'No ar há 2 dias: +38% de alcance vs. a média do projeto. Salvamentos acima da meta.',
      fields: ['Posts ao vivo', 'Alcance', 'Salvamentos', 'Alertas'] },
    { key: 'retrospective', label: 'Retrô', color: '#6366F1', icon: 'chart-line',
      summary: 'Rascunho da retro pronto: o gancho de bastidores puxou o alcance. Repetir o formato no próximo ciclo.',
      fields: ['Métricas finais', 'Acertos', 'Melhorias', 'Lições'] },
    { key: 'done', label: 'Concluído', color: '#14B8A6', icon: 'circle-check',
      summary: 'Arquivado com o histórico completo, os criativos e os aprendizados — pronto para virar case.',
      fields: ['Snapshot final', 'Histórico', 'Criativos'] }
  ].freeze

  # ── The AI Strategist demo (typewriter chat → generated tickets) ────
  STRATEGIST = {
    prompt: '2 reels e 1 carrossel por semana para o lançamento da Bloom, focados em prova social.',
    reply: 'Fechado. Montei um plano de 4 semanas — 12 tickets, cada um com brief, canais e subtarefas. Quer aplicar no quadro?',
    tickets: [
      { title: 'Reel — bastidores do produto', status: 'ideation',  color: '#F59E0B' },
      { title: 'Carrossel — 5 mitos do nicho',  status: 'scoping',   color: '#0EA5E9' },
      { title: 'Reel — depoimento de cliente',  status: 'ideation',  color: '#F59E0B' },
      { title: 'Reel — antes e depois',         status: 'scoping',   color: '#0EA5E9' },
      { title: 'Carrossel — passo a passo',     status: 'ideation',  color: '#F59E0B' },
      { title: 'Reel — respondendo dúvidas',    status: 'ideation',  color: '#F59E0B' }
    ]
  }.freeze

  # ── Pricing FAQ ─────────────────────────────────────────────────────
  # Trial length is interpolated from the single pricing source (Pricing) so it
  # stays in sync with billing without a copy change here.
  FAQS = [
    { q: 'Como funciona o período de teste?',
      a: "Você tem #{Pricing.trial_days} dias de teste em qualquer plano. É preciso cadastrar um cartão para começar — só cobramos ao fim do teste, e você pode cancelar antes quando quiser." },
    { q: 'O que são os créditos?',
      a: 'A geração de vídeos e imagens consome créditos pré-pagos da sua carteira. Cada plano já inclui uma cota mensal de créditos, e você pode comprar mais a qualquer momento. 1 crédito = R$ 1. Carrosséis e legendas com IA são inclusos, sem gastar créditos.' },
    { q: 'Existe plano gratuito?',
      a: "Não há plano gratuito permanente — todo workspace começa com #{Pricing.trial_days} dias de teste (com cartão). Depois disso, é necessário um plano ativo para usar o app." },
    { q: 'Posso gerenciar mais de uma agência?',
      a: 'Sim. Você pode ter vários workspaces — cada agência fica isolada, com seu próprio time, clientes e dados.' },
    { q: 'Quais redes sociais são suportadas?',
      a: 'Instagram, Facebook, Threads, TikTok, YouTube, LinkedIn e X — com publicação direta e integração nativa em cada rede.' },
    { q: 'Como recebo dos meus clientes?',
      a: 'Pelo Mercado Pago: Pix (com QR code), boleto ou cartão, com conciliação automática do pagamento.' },
    { q: 'Posso trocar de plano depois?',
      a: 'Sim, a qualquer momento. O preço acompanha o tamanho da sua operação.' }
  ].freeze

  # ── The main features (one detail page each) ────────────────────────
  FEATURES = [
    {
      slug: 'quadro', name: 'Quadro de produção', eyebrow: 'O funil', color: '#EC4899', icon: 'square-kanban',
      card: 'Kanban de 7 etapas com arrastar-e-soltar, chips por projeto e filtros poderosos.',
      headline: 'Seu conteúdo, do insight ao impacto — num quadro vivo.',
      subhead: 'Um Kanban de sete etapas onde cada ticket é uma peça de conteúdo. Arraste entre as colunas e a etapa muda; o resto da operação acompanha sozinho.',
      points: [
        { icon: 'square-kanban', title: 'Sete etapas coloridas',
          desc: 'Ideação, Escopo, Produção, Agendado, Postado, Retrô e Concluído — cada uma com sua cor e seus campos.' },
        { icon: 'folder',        title: 'Chips por projeto',
          desc: 'Cada card mostra o projeto e o cliente. Filtre por projeto, cliente, responsável, rede ou tipo de criativo.' },
        { icon: 'zap',           title: 'Arrastar é uma ação',
          desc: 'Mover um card dispara a transição de status, registra o histórico e atualiza o resumo de IA — automaticamente.' },
        { icon: 'list-checks',   title: 'Subtarefas e responsáveis',
          desc: "Quebre o trabalho em subtarefas atribuíveis que se agregam na tela 'Minhas tarefas' de cada pessoa." }
      ],
      highlights: ['Drag-and-drop fluido', 'Filtros combináveis', 'Histórico de cada transição', 'Tempo real entre o time']
    },
    {
      slug: 'estudio', name: 'Estúdio criativo', eyebrow: 'Geração com IA', color: '#7C3AED', icon: 'wand-sparkles',
      card: 'Gere carrosséis virais, vídeos UGC e imagens com a identidade da marca, sem sair do app.',
      headline: 'Um estúdio de criação com IA dentro da sua operação.',
      subhead: 'Carrosséis, vídeos UGC e imagens gerados com a identidade da marca, o @handle e o avatar do criador. Da ideia ao arquivo final sem trocar de ferramenta.',
      points: [
        { icon: 'image',    title: 'Carrosséis virais',
          desc: 'Geração com padrões de viralização: identidade da marca, @handle, avatar do criador e imagens de apoio — inclusos, sem gastar créditos.' },
        { icon: 'video',    title: 'Vídeos UGC',
          desc: 'Vídeos com avatar e voz realistas via HeyGen e HyperFrames, renderizados de forma assíncrona.' },
        { icon: 'palette',  title: 'Identidade aplicada',
          desc: 'Cores, logo, tom de voz e avatar padrão da marca aplicados automaticamente em cada peça.' },
        { icon: 'sparkles', title: 'Legendas por rede',
          desc: 'Variações de legenda com as regras de tamanho e hashtags específicas de cada rede social.' }
      ],
      highlights: ['Carrossel, vídeo e imagem', 'Identidade da marca aplicada', 'Renderização assíncrona', 'Vídeo e imagem por créditos']
    },
    {
      slug: 'inteligencia', name: 'Inteligência artificial', eyebrow: 'IA em cada etapa', color: '#F59E0B', icon: 'sparkles',
      card: 'Resumos contextuais, síntese de ideias, escopo automático, legendas e retrospectivas.',
      headline: 'A IA que entende o contexto de cada peça de conteúdo.',
      subhead: 'A IA trabalha em cada etapa do funil: sintetiza o brief, monta o escopo, escreve legendas por rede e transforma métricas em aprendizado.',
      points: [
        { icon: 'sparkles',    title: 'Resumo contextual',
          desc: 'Cada etapa do ticket ganha um resumo gerado pela IA que evolui junto com o conteúdo.' },
        { icon: 'lightbulb',   title: 'Síntese de ideias',
          desc: 'O brief vira ângulos e ganchos concretos, prontos para virar escopo.' },
        { icon: 'list-checks', title: 'Escopo automático',
          desc: 'Uma ideia vira um escopo com checklist de subtarefas, criado em segundos.' },
        { icon: 'chart-line',  title: 'Retrospectiva automática',
          desc: 'As métricas do post e o histórico viram uma retro com aprendizados para o próximo ciclo.' }
      ],
      highlights: ['Resumos por etapa', 'Ideias e escopo', 'Legendas por rede', 'Retrospectiva de performance']
    },
    {
      slug: 'publicacao', name: 'Publicação & analytics', eyebrow: 'Multi-rede', color: '#10B981', icon: 'send',
      card: 'Instagram, Facebook, Threads, TikTok, YouTube, LinkedIn e X — com integração direta.',
      headline: 'Publique em todas as redes e meça tudo num lugar só.',
      subhead: 'Agende e publique em cada rede social com integração direta e nativa, e acompanhe as métricas de cada post em tempo real.',
      points: [
        { icon: 'share-2',        title: 'Sete redes',
          desc: 'Instagram, Facebook, Threads, TikTok, YouTube, LinkedIn e X, com integração direta e nativa em cada uma.' },
        { icon: 'calendar-clock', title: 'Agendamento',
          desc: 'Programe a publicação no melhor horário e deixe o sistema publicar por você.' },
        { icon: 'bar-chart-3',    title: 'Métricas por post',
          desc: 'Alcance, visualizações, curtidas, comentários, compartilhamentos e salvamentos, sincronizados automaticamente.' },
        { icon: 'trending-up',    title: 'Monitoramento',
          desc: 'Snapshots datados das métricas acompanham a evolução de cada conteúdo no ar.' }
      ],
      highlights: ['7 redes sociais', 'Integração direta e nativa', 'Métricas sincronizadas', 'Histórico de performance']
    },
    {
      slug: 'estrategista', name: 'Estrategista de IA', eyebrow: 'Planejamento com IA', color: '#6366F1', icon: 'bot',
      card: 'Converse com o estrategista e transforme uma cadência em um mês inteiro de tickets prontos.',
      headline: 'Um estrategista de conteúdo que preenche seu quadro por você.',
      subhead: 'Diga a cadência e o objetivo — “2 reels e 1 carrossel por semana” — e o estrategista propõe um plano completo, com datas, briefs e subtarefas, pronto para aplicar em um clique.',
      points: [
        { icon: 'messages-square', title: 'Conversa que planeja',
          desc: 'Uma conversa multi-turno com um estrategista sênior que entende o contexto do projeto e da marca.' },
        { icon: 'workflow',        title: 'Um mês em segundos',
          desc: 'O plano vira dezenas de tickets agendados — cada um já em Ideação, com brief e canais definidos.' },
        { icon: 'list-checks',     title: 'Subtarefas incluídas',
          desc: 'Cada ticket proposto já traz o checklist de subtarefas com estimativa de esforço.' },
        { icon: 'sliders-horizontal', title: 'Edite e aplique',
          desc: 'Ajuste a proposta, aplique de uma vez ou descarte — a sessão fica salva para retomar depois.' }
      ],
      highlights: ['Conversa multi-turno', 'Plano de semanas em 1 clique', 'Briefs + subtarefas prontos', 'Baseado na marca e no histórico']
    },
    {
      slug: 'relatorios', name: 'Relatórios de projeto', eyebrow: 'Auditoria com IA', color: '#14B8A6', icon: 'file-text',
      card: 'Um deck de auditoria de fim de projeto: KPIs, acertos, gargalos e plano de ação, gerado pela IA.',
      headline: 'O fechamento do projeto vira um relatório que impressiona o cliente.',
      subhead: 'Ao concluir um projeto, a IA lê as métricas dos posts, o histórico dos tickets e as lições aprendidas e monta um relatório de performance com acertos, gargalos e próximos passos.',
      points: [
        { icon: 'gauge',        title: 'KPIs consolidados',
          desc: 'Alcance, engajamento e evolução do projeto reunidos em uma visão executiva.' },
        { icon: 'trophy',       title: 'Acertos e gargalos',
          desc: 'A IA identifica o que funcionou e onde a operação travou, com base nos dados reais.' },
        { icon: 'target',       title: 'Plano de ação',
          desc: 'Recomendações concretas do que repetir e do que ajustar no próximo ciclo.' },
        { icon: 'file-text',    title: 'Pronto para o cliente',
          desc: 'Um deck editável que a agência revisa e apresenta — sem montar relatório na mão.' }
      ],
      highlights: ['KPIs automáticos', 'Análise de IA', 'Acertos + gargalos', 'Deck pronto para apresentar']
    },
    {
      slug: 'calendario', name: 'Calendário & reuniões', eyebrow: 'Agenda unificada', color: '#0EA5E9', icon: 'calendar-days',
      card: 'Posts agendados e reuniões no mesmo lugar, com arrastar para reagendar.',
      headline: 'Posts e reuniões na mesma agenda — sem surpresas.',
      subhead: 'Veja tudo que está agendado num calendário único: publicações e reuniões com o cliente, com visão de mês e semana e arrastar para reagendar.',
      points: [
        { icon: 'calendar-days',  title: 'Visão de mês e semana',
          desc: 'Posts agendados e reuniões lado a lado, com arrastar-e-soltar para reagendar.' },
        { icon: 'users',          title: 'Reuniões com o cliente',
          desc: 'Crie reuniões no Google Calendar com link do Google Meet direto do app.' },
        { icon: 'calendar-clock', title: 'Reagende arrastando',
          desc: 'Mude a data de um post ou reunião só arrastando o card no calendário.' },
        { icon: 'clock',          title: 'Melhor horário',
          desc: 'Sugestões de melhor horário para publicar com base no histórico de performance.' }
      ],
      highlights: ['Posts + reuniões juntos', 'Google Calendar & Meet', 'Arrastar para reagendar', 'Visão mês / semana']
    },
    {
      slug: 'cobrancas', name: 'Cobranças', eyebrow: 'Financeiro', color: '#F97316', icon: 'receipt',
      card: 'Fature seus clientes via Mercado Pago (Pix, boleto, cartão) com conciliação automática.',
      headline: 'Fature seus clientes e receba via Pix — sem planilha.',
      subhead: 'Crie faturas ligadas a projetos, cobre por Pix, boleto ou cartão pelo Mercado Pago e deixe a conciliação acontecer sozinha.',
      points: [
        { icon: 'receipt',      title: 'Faturas por projeto',
          desc: 'Uma fatura pode cobrir um projeto, vários ou nenhum — com status claro do rascunho ao pago.' },
        { icon: 'zap',          title: 'Pix em primeiro lugar',
          desc: 'Cobrança Pix com QR code, além de boleto e cartão, tudo via Mercado Pago.' },
        { icon: 'repeat',       title: 'Conciliação automática',
          desc: 'Webhooks e uma varredura agendada confirmam o pagamento e atualizam o status sozinhos.' },
        { icon: 'shield-check', title: 'Status confiável',
          desc: 'O pagamento só é dado como pago após a reconciliação direta com o Mercado Pago.' }
      ],
      highlights: ['Pix, boleto e cartão', 'Conciliação automática', 'Faturas multi-projeto', 'Mercado Pago nativo']
    }
  ].freeze
end
