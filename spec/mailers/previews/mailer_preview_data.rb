# frozen_string_literal: true

# In-memory sample records for mailer previews, so /rails/mailers renders every
# branded email without depending on dev database state.
module MailerPreviewData
  module_function

  def user(name: "Ana Souza", email: "ana@exemplo.com")
    User.new(email: email, name: name)
  end

  def workspace(name: "Estúdio Aurora")
    ws = Workspace.new(name: name)
    owner = user
    ws.define_singleton_method(:owner) { owner }
    ws
  end

  def project(name: "Campanha de Verão")
    Project.new(name: name, color: "#EC4899")
  end

  def ticket
    proj = project
    t = Ticket.new(title: "Reel de lançamento do produto", status: :production, due_date: Date.new(2026, 7, 15))
    t.define_singleton_method(:id) { 42 }
    t.define_singleton_method(:project) { proj }
    t.define_singleton_method(:display_title) { title }
    t
  end

  def subtask
    tk = ticket
    s = Subtask.new(title: "Gravar narração em off", due_date: Date.new(2026, 7, 10))
    s.define_singleton_method(:ticket) { tk }
    s
  end

  def client(email: "contato@lojaxyz.com")
    Client.new(name: "Loja XYZ", email: email)
  end

  def invoice
    cli = client
    ws = workspace
    inv = Invoice.new(
      amount_cents: 248_900, description: "Gestão de redes sociais — Julho/2026",
      due_date: Date.new(2026, 7, 5), external_reference: "INV-9F3A21"
    )
    inv.define_singleton_method(:client) { cli }
    inv.define_singleton_method(:workspace) { ws }
    inv
  end

  def subscription
    Subscription.new(plan: :agencia, status: "trialing", trial_ends_at: Time.zone.local(2026, 7, 12, 10, 0, 0))
  end

  def generation(kind: :carousel)
    g = Generation.new(kind: kind)
    g.define_singleton_method(:creative) { nil }
    g
  end

  def meeting
    ws = workspace
    m = Meeting.new(
      title: "Kickoff da campanha", starts_at: Time.zone.local(2026, 7, 1, 14, 0, 0),
      ends_at: Time.zone.local(2026, 7, 1, 15, 0, 0), notes: "Alinhar pauta e cronograma."
    )
    m.define_singleton_method(:workspace) { ws }
    m.define_singleton_method(:meet_url) { "https://meet.google.com/abc-defg-hij" }
    m
  end

  def post
    tk = ticket
    sa = SocialAccount.new(provider: :instagram)
    p = Post.new(permalink: "https://www.instagram.com/p/Cxyz123/", caption: "Novidade no ar! 🚀")
    p.define_singleton_method(:ticket) { tk }
    p.define_singleton_method(:social_account) { sa }
    p.define_singleton_method(:failure_reason) { "Token de acesso expirado" }
    p
  end

  def note
    tk = ticket
    author = user(name: "Rui Lima", email: "rui@exemplo.com")
    n = Note.new(body: "Excelente trabalho @ana, podemos publicar!", kind: :comment)
    n.define_singleton_method(:ticket) { tk }
    n.define_singleton_method(:plain_body) { "Excelente trabalho, podemos publicar!" }
    n.define_singleton_method(:user) { author }
    n
  end
end
