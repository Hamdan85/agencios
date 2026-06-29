# frozen_string_literal: true

# ─────────────────────────────────────────────────────────────────────
# agencios demo seed — a believable creative agency, fully populated so
# every screen (board, ticket, calendar, studio, clients, billing…) is
# alive on first login.
#
#   Login:  demo@agencios.app  /  demo1234
# ─────────────────────────────────────────────────────────────────────

puts "🌱 Resetting demo data…"
[PostMetric, Post, Generation, Creative, Subtask, Note, TicketStatusLog, Ticket,
 InvoiceProject, Charge, Invoice, Meeting, Project, Client, SocialAccount,
 Session, Membership, Setting, Subscription, Workspace, User].each(&:delete_all)

# ── Users ────────────────────────────────────────────────────────────
owner = User.create!(email: "demo@agencios.app", password: "demo1234", name: "Marina Costa", confirmed_at: Time.current)
team = {
  rafael: User.create!(email: "rafael@agencios.app", password: "demo1234", name: "Rafael Lima", confirmed_at: Time.current),
  julia:  User.create!(email: "julia@agencios.app",  password: "demo1234", name: "Júlia Santos", confirmed_at: Time.current),
  pedro:  User.create!(email: "pedro@agencios.app",  password: "demo1234", name: "Pedro Alves", confirmed_at: Time.current),
  bia:    User.create!(email: "bia@agencios.app",    password: "demo1234", name: "Bia Rocha", confirmed_at: Time.current),
}

# ── Workspace + brand ────────────────────────────────────────────────
ws = Workspace.create!(
  name: "Estúdio Pulse", slug: "estudio-pulse", default_handle: "@estudiopulse",
  brand_primary_color: "#7C3AED", brand_secondary_color: "#EC4899",
  brand_voice: "Ousada, divertida e direta — falamos com a Gen Z sem perder a estratégia."
)
Setting.create!(workspace: ws, brand_tone: "energético", auto_publish_default: false,
                google_access_token: "demo-google-token", google_calendar_connected_at: 5.days.ago)
Subscription.create!(workspace: ws, plan: :agencia, status: "active", seats: 5,
                     current_period_end: 22.days.from_now, trial_ends_at: 9.days.ago)

Membership.create!(workspace: ws, user: owner, role: :owner)
Membership.create!(workspace: ws, user: team[:rafael], role: :admin)
Membership.create!(workspace: ws, user: team[:julia], role: :manager)
Membership.create!(workspace: ws, user: team[:pedro], role: :member)
Membership.create!(workspace: ws, user: team[:bia], role: :member)
assignees = [owner, team[:julia], team[:pedro], team[:bia]]

# ── Social accounts ──────────────────────────────────────────────────
{ instagram: "estudiopulse", facebook: "estudiopulse", tiktok: "estudiopulse",
  youtube: "EstudioPulse", linkedin: "estudio-pulse" }.each do |provider, handle|
  SocialAccount.create!(workspace: ws, provider: provider, username: handle, status: :connected,
                        external_user_id: "ext_#{SecureRandom.hex(4)}",
                        user_access_token: "tok_#{SecureRandom.hex(6)}",
                        token_expires_at: 50.days.from_now, last_synced_at: 2.hours.ago,
                        scopes: %w[read publish insights])
end

# ── Clients + projects ───────────────────────────────────────────────
client_data = [
  { name: "Açaí da Vila",     company: "Vila Foods Ltda",  email: "contato@acaidavila.com.br", phone: "(11) 98888-1010", color: "#7C3AED" },
  { name: "GymFit Academia",  company: "GymFit S.A.",      email: "mkt@gymfit.com.br",         phone: "(11) 97777-2020", color: "#10B981" },
  { name: "Bloom Cosméticos", company: "Bloom Beauty",     email: "social@bloom.com.br",       phone: "(21) 96666-3030", color: "#EC4899" },
  { name: "TechNova",         company: "TechNova Startup", email: "growth@technova.io",        phone: "(11) 95555-4040", color: "#0EA5E9" },
  { name: "Vinho & Cia",      company: "Adega Premium",    email: "marketing@vinhoecia.com",   phone: "(51) 94444-5050", color: "#F43F5E" },
]
clients = client_data.map do |c|
  cl = Client.create!(workspace: ws, name: c[:name], company: c[:company], email: c[:email],
                      phone: c[:phone], document: "12.345.678/0001-#{rand(10..99)}", status: :active,
                      notes: "Cliente desde #{rand(2022..2024)}. Foco em conteúdo orgânico + tráfego pago.")
  [cl, c[:color]]
end

projects = []
project_names = {
  "Açaí da Vila" => ["Verão Frutado", "Lançamento Tigela Fit"],
  "GymFit Academia" => ["Desafio 60 Dias", "Campanha Matrículas"],
  "Bloom Cosméticos" => ["Linha Glow", "UGC Influencers"],
  "TechNova" => ["Series A Buzz"],
  "Vinho & Cia" => ["Harmonização de Outono"],
}
clients.each do |client, color|
  project_names[client.name].each_with_index do |pname, i|
    projects << Project.create!(workspace: ws, client: client, name: pname, color: color,
                                status: :active, starts_on: rand(20..60).days.ago, ends_on: rand(20..90).days.from_now,
                                budget_cents: [350_000, 480_000, 720_000, 990_000].sample,
                                description: "Conteúdo mensal: reels, carrosséis e stories para #{client.name}.")
  end
end

# ── Tickets across the funnel ────────────────────────────────────────
puts "🎫 Creating tickets across the funnel…"

def summary_for(status, title)
  {
    "ideation" => "Ideia central forte para “#{title}”. O gancho aposta em curiosidade + prova social. Priorize um CTA claro nos 3 primeiros segundos.",
    "scoping" => "Escopo definido para “#{title}”: formato e canais alinhados. Falta travar o roteiro final e estimar esforço de edição.",
    "production" => "Produção de “#{title}” avançando bem. Legenda no tom da marca; revisar QA do criativo versus o brief antes de aprovar.",
    "scheduled" => "“#{title}” pronto e agendado. Horário escolhido cobre o pico de audiência. Conferir adaptação de legenda por rede.",
    "published" => "“#{title}” no ar com bom alcance inicial. Engajamento acima da média do perfil — vale impulsionar.",
    "retrospective" => "“#{title}” superou a meta de alcance. Replicar o gancho de abertura; melhorar a chamada para salvar o post.",
    "done" => "Case “#{title}” concluído: entregou awareness e saves acima do histórico. Boa referência para a próxima campanha.",
  }[status]
end

CHANNELS_POOL = [%w[instagram tiktok], %w[instagram], %w[instagram facebook], %w[instagram youtube], %w[tiktok], %w[instagram linkedin]]

ticket_blueprints = [
  ["Reel: 3 sabores de açaí que viralizaram", :ideation, "reel"],
  ["Carrossel: mitos sobre treino de hipertrofia", :ideation, "carousel"],
  ["Série UGC com nano influenciadoras", :scoping, "ugc_video"],
  ["Carrossel: rotina de skincare em 5 passos", :scoping, "carousel"],
  ["Reel: bastidores do desafio 60 dias", :production, "reel"],
  ["Anúncio: oferta de matrícula relâmpago", :production, "ad"],
  ["Story interativo: enquete de sabores", :production, "story"],
  ["Carrossel: harmonização vinho + queijos", :scheduled, "carousel"],
  ["Reel: receita tigela fit em 15s", :scheduled, "reel"],
  ["Feed: lançamento linha Glow", :scheduled, "feed_image"],
  ["Reel: depoimento de aluno transformação", :published, "reel"],
  ["Carrossel: 7 sinais de que seu skincare funciona", :published, "carousel"],
  ["UGC: unboxing TechNova", :published, "ugc_video"],
  ["Reel: trend dançante GymFit", :retrospective, "reel"],
  ["Carrossel: cases Series A TechNova", :retrospective, "carousel"],
  ["Feed: agradecimento 100k seguidores", :done, "feed_image"],
  ["Reel: melhores momentos do verão", :done, "reel"],
]

WORKFLOW_INT = Ticket::WORKFLOW.each_with_index.to_h

tickets = ticket_blueprints.each_with_index.map do |(title, status, ctype), idx|
  project = projects.sample
  channels = CHANNELS_POOL.sample
  assignee = assignees.sample
  status_s = status.to_s
  summaries = {}
  passed = Ticket::WORKFLOW[0..Ticket::WORKFLOW.index(status)]
  passed.last(3).each { |st| summaries[st.to_s] = summary_for(st.to_s, title) }

  fields = {
    "ideation" => { "brief" => "Brief de #{title}.", "objective" => ["Awareness", "Engajamento", "Conversão"].sample,
                    "target_persona" => "Gen Z urbana, 18-28", "content_pillar" => ["Educativo", "Entretenimento", "Prova social"].sample },
    "scoping" => { "creative_type" => ctype, "channels" => channels, "copy_brief" => "Gancho forte + CTA para salvar.",
                   "deliverables" => ["1 #{ctype}", "3 variações de legenda"] },
    "production" => { "caption" => "Você não vai acreditar no passo 3 👀 #{title}", "hashtags" => %w[viral fyp agencia],
                      "approval_status" => %w[pending approved changes_requested].sample },
    "scheduled" => { "scheduled_at" => (rand(1..10).days.from_now).iso8601, "auto_publish" => [true, false].sample,
                     "first_comment" => "Salva esse post pra não esquecer! 💜" },
  }

  t = Ticket.create!(
    workspace: ws, project: project, assignee: assignee, created_by: owner,
    title: title, status: status, priority: %i[low medium high].sample,
    position: idx, creative_type: ctype, channels: channels,
    due_date: rand(-3..14).days.from_now.to_date,
    scheduled_at: (%w[scheduled published done].include?(status_s) ? rand(1..12).days.from_now : nil),
    published_at: (%w[published retrospective done].include?(status_s) ? rand(1..8).days.ago : nil),
    ai_summaries: summaries, fields: fields
  )

  Ticket::WORKFLOW[0..Ticket::WORKFLOW.index(status)].each_cons(2) do |from, to|
    TicketStatusLog.create!(workspace: ws, ticket: t, user: assignee,
                            from_status: WORKFLOW_INT[from], to_status: WORKFLOW_INT[to],
                            created_at: rand(2..20).days.ago)
  end
  Note.create!(workspace: ws, ticket: t, user: nil, kind: :system, body: "Ticket criado.")
  Note.create!(workspace: ws, ticket: t, user: assignee, kind: :comment, body: "Bora alinhar o gancho antes de produzir? 🔥") if idx.even?
  Note.create!(workspace: ws, ticket: t, user: nil, kind: :ai, body: summary_for(status_s, title)) if summaries.any?
  t
end

# ── Subtasks ─────────────────────────────────────────────────────────
SUBTASK_TITLES = ["Escrever roteiro", "Definir trilha sonora", "Gravar cenas", "Editar corte final",
                  "Revisar legenda", "Aprovar com cliente", "Selecionar hashtags", "Exportar nos formatos"]
tickets.each do |t|
  next if %w[ideation done].include?(t.status)
  rand(3..6).times do |i|
    Subtask.create!(workspace: ws, ticket: t, assignee: assignees.sample,
                    title: SUBTASK_TITLES.sample, done: i < rand(1..3),
                    due_date: rand(1..10).days.from_now.to_date, position: i)
  end
end

# ── Creatives + generations ──────────────────────────────────────────
puts "🎨 Creating creatives + generations…"
tickets.each do |t|
  next unless %w[production scheduled published retrospective done].include?(t.status)
  kind = case t.creative_type
         when "carousel" then :carousel
         when "ugc_video", "reel" then :video
         else :image
         end
  status = t.status == "production" ? :generating : :ready
  creative = Creative.create!(workspace: ws, ticket: t, creative_type: t.creative_type,
                              source: :generated, status: status, provider: (kind == :video ? "heygen" : "image_gen"),
                              caption: t.fields.dig("production", "caption"),
                              metadata: { "slides" => (1..rand(4..7)).map { |i| { "index" => i, "image_url" => "https://picsum.photos/seed/ag#{t.id}#{i}/600/750", "headline" => "Slide #{i}" } } })
  Generation.create!(workspace: ws, user: t.assignee, creative: creative, kind: kind,
                     status: (status == :ready ? :completed : :processing),
                     provider: creative.provider, cost_cents: (kind == :image ? 0 : [25, 30, 45].sample),
                     metered_at: (kind == :image ? nil : Time.current),
                     params: { "ticket_id" => t.id }, result: { "ok" => true })
end
6.times do
  k = %i[carousel video image].sample
  Generation.create!(workspace: ws, user: assignees.sample, kind: k, status: :completed,
                     provider: (k == :video ? "heygen" : "image_gen"),
                     cost_cents: (k == :image ? 0 : [25, 30, 45].sample), metered_at: (k == :image ? nil : Time.current),
                     params: { "studio" => true }, created_at: rand(1..14).days.ago)
end

# ── Posts + metrics ──────────────────────────────────────────────────
puts "📡 Creating posts + metrics…"
accounts = ws.social_accounts.index_by(&:provider)
tickets.each do |t|
  next unless %w[published retrospective done].include?(t.status)
  t.channels.each do |ch|
    acct = accounts[ch] || ws.social_accounts.first
    next unless acct
    post = Post.create!(workspace: ws, ticket: t, social_account: acct, status: :published,
                        scheduled_at: t.published_at, published_at: t.published_at,
                        caption: t.fields.dig("production", "caption") || t.title,
                        external_post_id: "p_#{SecureRandom.hex(5)}",
                        permalink: "https://#{ch}.com/p/#{SecureRandom.hex(4)}", media: {})
    3.times do |d|
      base = rand(2000..18000)
      PostMetric.create!(post: post, captured_at: (3 - d).days.ago,
                         reach: base * (d + 1), views: base * (d + 1) + rand(500..3000),
                         likes: (base * 0.08).to_i * (d + 1), comments: rand(10..240),
                         shares: rand(5..120), saves: rand(20..600), raw: {})
    end
  end
end

# ── Meetings ─────────────────────────────────────────────────────────
puts "📅 Creating meetings…"
meeting_titles = ["Alinhamento mensal de pauta", "Apresentação de resultados", "Briefing nova campanha",
                  "Aprovação de criativos", "Planejamento trimestral"]
[2.days.from_now.change(hour: 10), 4.days.from_now.change(hour: 15), 6.days.from_now.change(hour: 11),
 3.days.ago.change(hour: 14), 8.days.ago.change(hour: 9)].each_with_index do |start, i|
  client = clients.sample.first
  Meeting.create!(workspace: ws, client: client, project: client.projects.first,
                  title: meeting_titles[i % meeting_titles.size], starts_at: start, ends_at: start + 1.hour,
                  google_event_id: "evt_#{SecureRandom.hex(5)}", meet_url: "https://meet.google.com/#{SecureRandom.hex(3)}-#{SecureRandom.hex(3)}",
                  attendees: [{ "name" => owner.name, "email" => owner.email }, { "name" => client.name, "email" => client.email }],
                  notes: "Pauta: revisar entregáveis do mês e próximos passos.")
end

# ── Invoices + charges ───────────────────────────────────────────────
puts "💸 Creating invoices…"
invoice_specs = [
  [:paid, 480_000, 12.days.ago], [:open, 350_000, 6.days.from_now], [:open, 720_000, 9.days.from_now],
  [:overdue, 290_000, 4.days.ago], [:paid, 990_000, 20.days.ago], [:draft, 150_000, 15.days.from_now],
]
invoice_specs.each_with_index do |(status, cents, due), i|
  client = clients[i % clients.size].first
  inv = Invoice.create!(workspace: ws, client: client, status: status, amount_cents: cents, currency: "BRL",
                        description: "Pacote de conteúdo mensal — #{client.name}", due_date: due.to_date,
                        external_reference: "INV-#{SecureRandom.hex(4).upcase}")
  inv.projects << client.projects.first if client.projects.any?
  Charge.create!(workspace: ws, invoice: inv, mp_payment_id: "mp_#{SecureRandom.hex(6)}",
                 method: :pix, status: (status == :paid ? "approved" : "pending"), amount_cents: cents,
                 pix_qr_code: "00020126360014BR.GOV.BCB.PIX0114+5511988881010520400005303986540#{cents}5802BR5913ESTUDIO PULSE6009SAO PAULO62070503***6304ABCD",
                 pix_qr_code_base64: nil, ticket_url: "https://mercadopago.com/pix/#{SecureRandom.hex(5)}",
                 expires_at: 1.day.from_now)
end

puts "✅ Seed complete!"
puts "   Workspace: #{ws.name}  ·  #{ws.tickets.count} tickets  ·  #{ws.clients.count} clients  ·  #{ws.projects.count} projects"
puts "   Generations: #{ws.generations.count}  ·  Posts: #{ws.posts.count}  ·  Invoices: #{ws.invoices.count}  ·  Meetings: #{ws.meetings.count}"
puts "   Login → demo@agencios.app / demo1234"
