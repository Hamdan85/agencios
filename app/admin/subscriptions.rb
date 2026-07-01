# frozen_string_literal: true

ActiveAdmin.register Subscription do
  menu parent: "Tenants", label: "Assinaturas", priority: 2
  actions :index, :show

  filter :workspace, collection: -> { Workspace.order(:name) }
  filter :plan, as: :select, collection: Subscription.plans.keys
  filter :status
  filter :card_on_file
  filter :current_period_end
  filter :created_at

  scope :all, default: true
  scope("Ativas") { |s| s.where(status: "active") }
  scope("Em trial") { |s| s.where(status: "trialing") }
  scope("Inadimplentes") { |s| s.where(status: "past_due") }
  scope("Canceladas") { |s| s.where(status: "canceled") }

  index do
    id_column
    column("Workspace") { |s| link_to(s.workspace.name, admin_workspace_path(s.workspace)) }
    column :plan
    column :status
    column("Cartão") { |s| s.card_on_file? ? "Sim" : "Não" }
    column :seats
    column("Acesso") { |s| status_tag(s.access_granted? ? "sim" : "não", class: s.access_granted? ? "yes" : "error") }
    column :current_period_end
    column :created_at
  end

  show do
    attributes_table do
      row("Workspace") { |s| link_to(s.workspace.name, admin_workspace_path(s.workspace)) }
      row :plan
      row :status
      row("Acesso liberado") { |s| s.access_granted? ? "Sim" : "Não" }
      row("Cartão no arquivo") { |s| s.card_on_file? ? "Sim" : "Não" }
      row :seats
      row :trial_ends_at
      row :current_period_end
      row :cancel_at
      row :stripe_customer_id
      row :stripe_subscription_id
      row :created_at
    end
  end
end
