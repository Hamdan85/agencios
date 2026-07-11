# frozen_string_literal: true

ActiveAdmin.register CreditTransaction do
  menu parent: I18n.t('admin.menu.tenants'), label: I18n.t('admin.credit_transactions.menu'), priority: 4
  actions :index, :show

  filter :workspace, collection: -> { Workspace.order(:name) }
  filter :kind, as: :select, collection: CreditTransaction::KINDS
  filter :created_at

  scope :all, default: true
  scope(I18n.t('admin.credit_transactions.scope_debits')) { |s| s.where(kind: 'debit') }
  scope(I18n.t('admin.credit_transactions.scope_purchases')) { |s| s.where(kind: 'purchase') }
  scope(I18n.t('admin.credit_transactions.scope_grants')) { |s| s.where(kind: %w[grant adjustment]) }

  index do
    id_column
    column(I18n.t('admin.common.workspace')) { |t| link_to(t.workspace.name, admin_workspace_path(t.workspace)) }
    column :kind
    column :bucket
    column(I18n.t('admin.credit_transactions.col_amount'), &:amount)
    column(I18n.t('admin.credit_transactions.col_balance'), &:balance_after)
    column(I18n.t('admin.common.generation')) do |t|
      t.generation_id ? link_to("##{t.generation_id}", admin_generation_path(t.generation_id)) : '—'
    end
    column :description
    column :created_at
  end

  show do
    attributes_table do
      row(I18n.t('admin.common.workspace')) { |t| link_to(t.workspace.name, admin_workspace_path(t.workspace)) }
      row :kind
      row :bucket
      row :amount
      row :granted_delta
      row :purchased_delta
      row :balance_after
      row :expires_at
      row :description
      row(I18n.t('admin.common.generation')) do |t|
        t.generation_id ? link_to("##{t.generation_id}", admin_generation_path(t.generation_id)) : '—'
      end
      row(I18n.t('admin.common.user')) { |t| t.user&.email }
      row :created_at
    end
  end
end
