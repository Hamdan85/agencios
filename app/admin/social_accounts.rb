# frozen_string_literal: true

ActiveAdmin.register SocialAccount do
  menu parent: "Tenants", label: "Contas sociais", priority: 6
  actions :index, :show

  filter :workspace, collection: -> { Workspace.order(:name) }
  filter :provider, as: :select, collection: -> { SocialAccount.distinct.pluck(:provider).compact }
  filter :status
  filter :token_expires_at
  filter :created_at

  scope :all, default: true
  scope("Token expirado") { |s| s.where.not(token_expires_at: nil).where(token_expires_at: ..Time.current) }
  scope("Revogadas") { |s| s.where.not(revoked_at: nil) }

  index do
    id_column
    column("Workspace") { |a| link_to(a.workspace.name, admin_workspace_path(a.workspace)) }
    column :provider
    column :username
    column :status
    column("Token expira") { |a| a.token_expires_at }
    column("Expirado?") { |a| a.token_expired? ? status_tag("sim", class: "error") : "não" }
    column :last_synced_at
  end

  show do
    # LGPD: OAuth tokens are encrypted and intentionally NOT displayed.
    attributes_table do
      row("Workspace") { |a| link_to(a.workspace.name, admin_workspace_path(a.workspace)) }
      row("Cliente") { |a| a.client&.name }
      row :provider
      row :username
      row :display_name
      row :status
      row :connection_type
      row("Token expira em") { |a| a.token_expires_at }
      row("Token expirado?") { |a| a.token_expired? ? "Sim" : "Não" }
      row :last_synced_at
      row :revoked_at
      row :created_at
    end
  end
end
