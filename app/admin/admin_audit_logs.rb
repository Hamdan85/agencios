# frozen_string_literal: true

ActiveAdmin.register AdminAuditLog do
  menu parent: "Plataforma", label: "Auditoria", priority: 9
  actions :index, :show

  config.sort_order = "created_at_desc"

  filter :action, as: :select, collection: -> { AdminAuditLog.distinct.pluck(:action).compact }
  filter :staff_user, collection: -> { User.where(staff: true).order(:email) }
  filter :target_type
  filter :created_at

  index do
    id_column
    column("Equipe") { |l| l.staff_user&.email }
    column :action
    column("Alvo") { |l| l.target_type ? "#{l.target_type}##{l.target_id}" : "—" }
    column("Detalhes") { |l| l.metadata.presence&.to_json }
    column :ip_address
    column :created_at
  end

  show do
    attributes_table do
      row("Equipe") { |l| l.staff_user&.email }
      row :action
      row("Alvo") { |l| l.target_type ? "#{l.target_type}##{l.target_id}" : "—" }
      row("Detalhes") { |l| l.metadata.presence&.to_json }
      row :ip_address
      row :created_at
    end
  end
end
