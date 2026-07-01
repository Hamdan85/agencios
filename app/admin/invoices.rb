# frozen_string_literal: true

ActiveAdmin.register Invoice do
  menu parent: "Tenants", label: "Faturas (clientes)", priority: 7
  actions :index, :show

  filter :workspace, collection: -> { Workspace.order(:name) }
  filter :status, as: :select, collection: Invoice.statuses.keys
  filter :due_date
  filter :created_at

  index do
    id_column
    column("Workspace") { |i| link_to(i.workspace.name, admin_workspace_path(i.workspace)) }
    column("Cliente") { |i| i.client&.name }
    column :status
    column("Valor (¢)") { |i| i.amount_cents }
    column :currency
    column :due_date
    column :created_at
  end

  show do
    attributes_table do
      row("Workspace") { |i| link_to(i.workspace.name, admin_workspace_path(i.workspace)) }
      row("Cliente") { |i| i.client&.name }
      row :status
      row :amount_cents
      row :currency
      row :description
      row :due_date
      row :created_at
    end
  end
end
