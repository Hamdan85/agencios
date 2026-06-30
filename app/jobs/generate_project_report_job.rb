# frozen_string_literal: true

# Generates a project's end-of-run audit report. Enqueued by
# Operations::Projects::Finalize after the report row is created (generating).
class GenerateProjectReportJob < ApplicationJob
  queue_as :default

  def perform(report_id)
    report = ProjectReport.find_by(id: report_id)
    return unless report

    Operations::Reports::GenerateProjectReport.call(report: report)
  end
end
