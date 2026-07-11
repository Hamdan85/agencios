# frozen_string_literal: true

ActiveAdmin.register Subscription do
  menu parent: I18n.t('admin.menu.tenants'), label: I18n.t('admin.subscriptions.menu'), priority: 2
  actions :index, :show

  filter :workspace, collection: -> { Workspace.order(:name) }
  filter :plan, as: :select, collection: Subscription.plans.keys
  filter :status
  filter :card_on_file
  filter :current_period_end
  filter :created_at

  scope :all, default: true
  scope(I18n.t('admin.subscriptions.scope_active')) { |s| s.where(status: 'active') }
  scope(I18n.t('admin.subscriptions.scope_trialing')) { |s| s.where(status: 'trialing') }
  scope(I18n.t('admin.subscriptions.scope_past_due')) { |s| s.where(status: 'past_due') }
  scope(I18n.t('admin.subscriptions.scope_canceled')) { |s| s.where(status: 'canceled') }

  index do
    id_column
    column(I18n.t('admin.common.workspace')) { |s| link_to(s.workspace.name, admin_workspace_path(s.workspace)) }
    column :plan
    column :status
    column(I18n.t('admin.subscriptions.col_card')) { |s| s.card_on_file? ? I18n.t('admin.common.yes') : I18n.t('admin.common.no') }
    column :seats
    column(I18n.t('admin.subscriptions.col_access')) { |s| status_tag(s.access_granted? ? I18n.t('admin.common.yes_tag') : I18n.t('admin.common.no_tag'), class: s.access_granted? ? 'yes' : 'error') }
    column :current_period_end
    column :created_at
  end

  show do
    attributes_table do
      row(I18n.t('admin.common.workspace')) { |s| link_to(s.workspace.name, admin_workspace_path(s.workspace)) }
      row :plan
      row :status
      row(I18n.t('admin.subscriptions.row_access')) { |s| s.access_granted? ? I18n.t('admin.common.yes') : I18n.t('admin.common.no') }
      row(I18n.t('admin.subscriptions.row_card')) { |s| s.card_on_file? ? I18n.t('admin.common.yes') : I18n.t('admin.common.no') }
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
