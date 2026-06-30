# frozen_string_literal: true

module Operations
  module Projects
    # The single authoritative "finalize a project" transition. Moves the project
    # to `completed`, stamps `completed_at`, then kicks off the end-of-run audit
    # report. Idempotent-ish: re-finalizing just regenerates a fresh report.
    class Finalize < Operations::Base
      def initialize(project:, user: nil)
        @project = project
        @user = user
      end

      def call
        @project.update!(status: :completed, completed_at: @project.completed_at || Time.current)

        report = enqueue_report
        Broadcaster.board(@project.workspace_id, "project_finalized", project_id: @project.id)
        report
      end

      private

      # Create the report row up front (status: generating) so the UI has
      # something to navigate to immediately, then generate it in the background.
      def enqueue_report
        report = @project.reports.create!(
          workspace: @project.workspace,
          status: :generating,
          period_start: report_period_start,
          period_end: Date.current
        )
        GenerateProjectReportJob.perform_later(report.id)
        report
      rescue StandardError => e
        Rails.logger.warn("[Projects::Finalize] could not enqueue report: #{e.class}: #{e.message}")
        nil
      end

      # Default reporting window: the project's run, falling back to the last 90
      # days when no start date is set (matches the deck's "90 dias" framing).
      def report_period_start
        @project.starts_on || 90.days.ago.to_date
      end
    end
  end
end
