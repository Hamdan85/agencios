# frozen_string_literal: true

ActiveAdmin.register User do
  menu parent: "Plataforma", label: "Usuários", priority: 2

  # Read + a guarded staff toggle. Never edit credentials here.
  actions :index, :show, :edit, :update
  permit_params :staff

  filter :email_cont, label: "E-mail contém"
  filter :name_cont, label: "Nome contém"
  filter :staff
  filter :confirmed_at
  filter :created_at

  index do
    selectable_column
    id_column
    column :email
    column :name
    column("Equipe") { |u| status_tag(u.staff? ? "staff" : "—", class: u.staff? ? "yes" : "") }
    column("Confirmado") { |u| u.confirmed_at ? "Sim" : "Não" }
    column("Workspaces") { |u| u.memberships.count }
    column :created_at
    actions defaults: true do |user|
      unless user.staff?
        span " "
        span button_to("Personificar", admin_impersonate_path(user), method: :post,
                       form: { style: "display:inline" },
                       class: "button", data: { confirm: "Entrar como #{user.email}?" })
      end
    end
  end

  show do
    attributes_table do
      row :id
      row :email
      row :name
      row("Equipe (staff)") { |u| u.staff? ? "Sim" : "Não" }
      row("E-mail confirmado") { |u| u.confirmed_at ? "Sim (#{u.confirmed_at})" : "Não" }
      row("Google conectado") { |u| u.google_uid.present? ? "Sim" : "Não" }
      row :created_at
      # LGPD: tokens/secrets deliberately never rendered.
    end

    panel "Workspaces" do
      table_for user.memberships.includes(:workspace) do
        column("Workspace") { |m| link_to(m.workspace.name, admin_workspace_path(m.workspace)) }
        column("Papel") { |m| m.role }
        column("Desde") { |m| m.created_at.to_date }
      end
    end

    unless user.staff?
      div class: "action_items" do
        span button_to("Personificar este usuário", admin_impersonate_path(user), method: :post,
                       class: "button", data: { confirm: "Entrar como #{user.email}?" })
      end
    end

    active_admin_comments
  end

  # Guardrail: log any staff-flag change.
  after_save do |user|
    if user.saved_change_to_staff?
      AdminAuditLog.record(
        staff_user: current_staff_user, action: "toggle_staff", target: user,
        metadata: { staff: user.staff? }, ip_address: request.remote_ip
      )
    end
  end
end
