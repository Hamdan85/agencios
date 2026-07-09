# frozen_string_literal: true

module Controllers
  module Public
    module Portal
      # The central's landing payload: the agency's brand + the list of the
      # client's campaigns with their status-driven available views.
      class Show < Base
        def call
          pending_by_project = @client.pending_approval_tickets.group_by(&:project_id).transform_values(&:size)
          {
            agency: agency,
            client: { name: @client.name },
            campaigns: ordered_projects.map { |project| campaign_payload(project, pending_by_project[project.id].to_i) }
          }
        end

        private

        # Active/paused first (live work), then completed, then archived; newest
        # within each bucket.
        def ordered_projects
          order = { 'active' => 0, 'paused' => 1, 'completed' => 2, 'archived' => 3 }
          visible_projects.to_a.sort_by { |p| [order[p.status] || 9, -p.created_at.to_i] }
        end

        def campaign_payload(project, pending_count)
          report = project.latest_report
          has_ready_report = report&.status_ready?
          {
            id: project.id,
            name: project.name,
            color: project.color,
            status: project.status,
            status_label: Controllers::Public::Portal::STATUS_LABELS[project.status],
            counts: { tickets: project.tickets.size, pending_approval: pending_count },
            has_report: has_ready_report,
            available_tabs: available_tabs(project, pending_count, has_ready_report),
            period: { starts_on: project.starts_on&.iso8601, completed_at: project.completed_at&.iso8601 }
          }
        end

        # Status drives which views the client can open:
        #   active/paused → quadro (read-only board), aprovações (when pending),
        #                   métricas (real-time);
        #   completed     → só o relatório da campanha;
        #   archived      → relatório se pronto, senão o quadro.
        def available_tabs(project, pending_count, has_ready_report)
          case project.status
          when 'completed'
            ['relatorio']
          when 'archived'
            has_ready_report ? ['relatorio'] : ['quadro']
          else
            tabs = ['quadro']
            tabs << 'aprovacoes' if pending_count.positive?
            tabs << 'metricas'
            tabs
          end
        end
      end
    end
  end
end
