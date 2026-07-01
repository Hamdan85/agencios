# frozen_string_literal: true

ActiveAdmin.register CreditTransaction do
  menu parent: 'Tenants', label: 'Créditos (ledger)', priority: 4
  actions :index, :show

  filter :workspace, collection: -> { Workspace.order(:name) }
  filter :kind, as: :select, collection: CreditTransaction::KINDS
  filter :created_at

  scope :all, default: true
  scope('Débitos') { |s| s.where(kind: 'debit') }
  scope('Compras') { |s| s.where(kind: 'purchase') }
  scope('Concessões') { |s| s.where(kind: %w[grant adjustment]) }

  index do
    id_column
    column('Workspace') { |t| link_to(t.workspace.name, admin_workspace_path(t.workspace)) }
    column :kind
    column :bucket
    column('Valor', &:amount)
    column('Saldo após', &:balance_after)
    column('Geração') do |t|
      t.generation_id ? link_to("##{t.generation_id}", admin_generation_path(t.generation_id)) : '—'
    end
    column :description
    column :created_at
  end

  show do
    attributes_table do
      row('Workspace') { |t| link_to(t.workspace.name, admin_workspace_path(t.workspace)) }
      row :kind
      row :bucket
      row :amount
      row :granted_delta
      row :purchased_delta
      row :balance_after
      row :expires_at
      row :description
      row('Geração') do |t|
        t.generation_id ? link_to("##{t.generation_id}", admin_generation_path(t.generation_id)) : '—'
      end
      row('Usuário') { |t| t.user&.email }
      row :created_at
    end
  end
end
