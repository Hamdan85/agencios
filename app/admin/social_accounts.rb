# frozen_string_literal: true

ActiveAdmin.register SocialAccount do
  menu parent: I18n.t('admin.menu.tenants'), label: I18n.t('admin.social_accounts.menu'), priority: 6
  actions :index, :show

  filter :workspace, collection: -> { Workspace.order(:name) }
  filter :provider, as: :select, collection: -> { SocialAccount.distinct.pluck(:provider).compact }
  filter :status
  filter :token_expires_at
  filter :created_at

  scope :all, default: true
  scope(I18n.t('admin.social_accounts.scope_expired')) { |s| s.where.not(token_expires_at: nil).where(token_expires_at: ..Time.current) }
  scope(I18n.t('admin.social_accounts.scope_revoked')) { |s| s.where.not(revoked_at: nil) }

  index do
    id_column
    column(I18n.t('admin.common.workspace')) { |a| link_to(a.workspace.name, admin_workspace_path(a.workspace)) }
    column :provider
    column :username
    column :status
    column(I18n.t('admin.social_accounts.col_token_expires'), &:token_expires_at)
    column(I18n.t('admin.social_accounts.col_expired')) { |a| a.token_expired? ? status_tag(I18n.t('admin.common.yes_tag'), class: 'error') : I18n.t('admin.common.no_tag') }
    column :last_synced_at
  end

  show do
    # LGPD: OAuth tokens are encrypted and intentionally NOT displayed.
    attributes_table do
      row(I18n.t('admin.common.workspace')) { |a| link_to(a.workspace.name, admin_workspace_path(a.workspace)) }
      row(I18n.t('admin.common.client')) { |a| a.client&.name }
      row :provider
      row :username
      row :display_name
      row :status
      row :connection_type
      row(I18n.t('admin.social_accounts.row_token_expires'), &:token_expires_at)
      row(I18n.t('admin.social_accounts.row_token_expired')) { |a| a.token_expired? ? I18n.t('admin.common.yes') : I18n.t('admin.common.no') }
      row :last_synced_at
      row :revoked_at
      row :created_at
    end
  end
end
