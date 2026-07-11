# frozen_string_literal: true

ActiveAdmin.register Membership do
  menu parent: I18n.t('admin.menu.tenants'), label: I18n.t('admin.memberships.menu'), priority: 5
  actions :index, :show

  filter :workspace, collection: -> { Workspace.order(:name) }
  filter :role, as: :select, collection: Membership.roles.keys
  filter :created_at

  index do
    id_column
    column(I18n.t('admin.common.workspace')) { |m| link_to(m.workspace.name, admin_workspace_path(m.workspace)) }
    column(I18n.t('admin.common.user')) { |m| link_to(m.user.email, admin_user_path(m.user)) }
    column :role
    column :created_at
  end

  show do
    attributes_table do
      row(I18n.t('admin.common.workspace')) { |m| link_to(m.workspace.name, admin_workspace_path(m.workspace)) }
      row(I18n.t('admin.common.user')) { |m| link_to(m.user.email, admin_user_path(m.user)) }
      row :role
      row :created_at
    end
  end
end
