# frozen_string_literal: true

ActiveAdmin.register Generation do
  menu parent: "Tenants", label: "Gerações", priority: 3
  actions :index, :show

  filter :workspace, collection: -> { Workspace.order(:name) }
  filter :kind, as: :select, collection: Generation.kinds.keys
  filter :status, as: :select, collection: Generation.statuses.keys
  filter :provider
  filter :created_at

  scope :all, default: true
  scope("Vídeos") { |s| s.where(kind: :video) }
  scope("Imagens") { |s| s.where(kind: :image) }
  scope("Carrosséis") { |s| s.where(kind: :carousel) }
  scope("Falhas") { |s| s.where(status: :failed) }

  index do
    id_column
    column("Workspace") { |g| link_to(g.workspace.name, admin_workspace_path(g.workspace)) }
    column :kind
    column :status
    column :provider
    column("Custo (¢US$)") { |g| g.cost_cents }
    column("Metered") { |g| g.metered? ? "Sim" : "—" }
    column :created_at
  end

  show do
    attributes_table do
      row("Workspace") { |g| link_to(g.workspace.name, admin_workspace_path(g.workspace)) }
      row("Usuário") { |g| g.user&.email }
      row :kind
      row :status
      row :provider
      row :external_id
      row :cost_cents
      row :metered_at
      row :failure_reason
      row :created_at
    end
    panel "Créditos desta geração" do
      table_for generation.workspace.credit_transactions.where(generation_id: generation.id).order(:created_at) do
        column(:kind)
        column(:amount)
        column(:balance_after)
        column(:description)
        column(:created_at)
      end
    end
  end
end
