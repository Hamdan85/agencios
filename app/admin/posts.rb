# frozen_string_literal: true

ActiveAdmin.register Post do
  menu parent: 'Tenants', label: 'Posts', priority: 8
  actions :index, :show

  filter :workspace, collection: -> { Workspace.order(:name) }
  filter :status, as: :select, collection: Post.statuses.keys
  filter :scheduled_at
  filter :published_at
  filter :created_at

  scope :all, default: true
  scope('Agendados') { |s| s.where(status: :scheduled) }
  scope('Publicados') { |s| s.where(status: :published) }
  scope('Falhas') { |s| s.where(status: :failed) }

  index do
    id_column
    column('Workspace') { |p| link_to(p.workspace.name, admin_workspace_path(p.workspace)) }
    column :status
    column :scheduled_at
    column :published_at
    column('Permalink') do |p|
      p.permalink.present? ? link_to('abrir', p.permalink, target: '_blank', rel: 'noopener') : '—'
    end
    column :created_at
  end

  show do
    attributes_table do
      row('Workspace') { |p| link_to(p.workspace.name, admin_workspace_path(p.workspace)) }
      row :status
      row :scheduled_at
      row :published_at
      row :external_post_id
      row('Permalink') do |p|
        p.permalink.present? ? link_to(p.permalink, p.permalink, target: '_blank', rel: 'noopener') : '—'
      end
      row :failure_reason
      row :created_at
    end
  end
end
