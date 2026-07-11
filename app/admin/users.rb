# frozen_string_literal: true

ActiveAdmin.register User do
  menu parent: I18n.t('admin.menu.platform'), label: I18n.t('admin.users.menu'), priority: 2

  # Read + a guarded staff toggle. Never edit credentials here.
  actions :index, :show, :edit, :update
  permit_params :staff

  filter :email_cont, label: I18n.t('admin.users.filter_email')
  filter :name_cont, label: I18n.t('admin.users.filter_name')
  filter :staff
  filter :confirmed_at
  filter :created_at

  index do
    selectable_column
    id_column
    column :email
    column :name
    column(I18n.t('admin.users.col_team')) { |u| status_tag(u.staff? ? I18n.t('admin.users.team_staff') : '—', class: u.staff? ? 'yes' : '') }
    column(I18n.t('admin.users.col_confirmed')) { |u| u.confirmed_at ? I18n.t('admin.common.yes') : I18n.t('admin.common.no') }
    column(I18n.t('admin.users.col_workspaces')) { |u| u.memberships.count }
    column :created_at
    actions defaults: true do |user|
      unless user.staff?
        span ' '
        span button_to(I18n.t('admin.users.impersonate'), admin_impersonate_path(user), method: :post,
                                                                     form: { style: 'display:inline' },
                                                                     class: 'button', data: { confirm: I18n.t('admin.common.impersonate_confirm', email: user.email) })
      end
    end
  end

  show do
    attributes_table do
      row :id
      row :email
      row :name
      row(I18n.t('admin.users.row_team')) { |u| u.staff? ? I18n.t('admin.common.yes') : I18n.t('admin.common.no') }
      row(I18n.t('admin.users.row_email_confirmed')) { |u| u.confirmed_at ? I18n.t('admin.users.email_confirmed_yes', at: u.confirmed_at) : I18n.t('admin.common.no') }
      row(I18n.t('admin.users.row_google')) { |u| u.google_uid.present? ? I18n.t('admin.common.yes') : I18n.t('admin.common.no') }
      row :created_at
      # LGPD: tokens/secrets deliberately never rendered.
    end

    panel I18n.t('admin.users.workspaces_panel') do
      table_for user.memberships.includes(:workspace) do
        column(I18n.t('admin.common.workspace')) { |m| link_to(m.workspace.name, admin_workspace_path(m.workspace)) }
        column(I18n.t('admin.common.role'), &:role)
        column(I18n.t('admin.users.ws_since')) { |m| m.created_at.to_date }
      end
    end

    unless user.staff?
      div class: 'action_items' do
        span button_to(I18n.t('admin.users.impersonate_this'), admin_impersonate_path(user), method: :post,
                                                                                  class: 'button', data: { confirm: I18n.t('admin.common.impersonate_confirm', email: user.email) })
      end
    end
  end

  # Guardrail: log any staff-flag change.
  after_save do |user|
    if user.saved_change_to_staff?
      AdminAuditLog.record(
        staff_user: current_staff_user, action: 'toggle_staff', target: user,
        metadata: { staff: user.staff? }, ip_address: request.remote_ip
      )
    end
  end
end
