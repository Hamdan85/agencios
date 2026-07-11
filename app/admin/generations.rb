# frozen_string_literal: true

ActiveAdmin.register Generation do
  menu parent: I18n.t('admin.menu.tenants'), label: I18n.t('admin.generations.menu'), priority: 3
  actions :index, :show

  filter :workspace, collection: -> { Workspace.order(:name) }
  filter :kind, as: :select, collection: Generation.kinds.keys
  filter :status, as: :select, collection: Generation.statuses.keys
  filter :provider
  filter :created_at

  scope :all, default: true
  scope(I18n.t('admin.generations.scope_videos')) { |s| s.where(kind: :video) }
  scope(I18n.t('admin.generations.scope_images')) { |s| s.where(kind: :image) }
  scope(I18n.t('admin.generations.scope_carousels')) { |s| s.where(kind: :carousel) }
  scope(I18n.t('admin.generations.scope_failed')) { |s| s.where(status: :failed) }

  index do
    id_column
    column(I18n.t('admin.common.workspace')) { |g| link_to(g.workspace.name, admin_workspace_path(g.workspace)) }
    column :kind
    column :status
    column :provider
    column(I18n.t('admin.generations.col_cost'), &:cost_cents)
    column :created_at
  end

  show do
    attributes_table do
      row(I18n.t('admin.common.workspace')) { |g| link_to(g.workspace.name, admin_workspace_path(g.workspace)) }
      row(I18n.t('admin.common.user')) { |g| g.user&.email }
      row :kind
      row :status
      row :provider
      row :external_id
      row :cost_cents
      row :failure_reason
      row :created_at
    end
    panel I18n.t('admin.generations.credits_panel') do
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
