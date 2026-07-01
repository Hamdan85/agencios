# frozen_string_literal: true

ActiveAdmin.register Membership do
  menu parent: 'Tenants', label: 'Membros', priority: 5
  actions :index, :show

  filter :workspace, collection: -> { Workspace.order(:name) }
  filter :role, as: :select, collection: Membership.roles.keys
  filter :created_at

  index do
    id_column
    column('Workspace') { |m| link_to(m.workspace.name, admin_workspace_path(m.workspace)) }
    column('Usuário') { |m| link_to(m.user.email, admin_user_path(m.user)) }
    column :role
    column :created_at
  end

  show do
    attributes_table do
      row('Workspace') { |m| link_to(m.workspace.name, admin_workspace_path(m.workspace)) }
      row('Usuário') { |m| link_to(m.user.email, admin_user_path(m.user)) }
      row :role
      row :created_at
    end
  end
end
