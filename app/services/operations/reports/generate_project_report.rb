# frozen_string_literal: true

module Operations
  module Reports
    # Assembles a project's end-of-run audit report: computes the quantitative
    # block, asks Claude for the qualitative sections, merges both into the
    # report's `data`, and broadcasts. Following the AI pipeline's "never break on
    # an AI outage" rule, the numbers are always persisted; the AI sections are
    # merged in only when the model returns parseable JSON.
    #
    # Shape of `data`:
    #   { period:, kpis:, content:, totals:, format_breakdown:,   # computed
    #     wins:, content_performance:, bottlenecks:, opportunities:,
    #     matrix:, overall:, action_plan:, projection:, growth_angle:, # AI
    #     ai_ok: <bool> }
    class GenerateProjectReport < Operations::Base
      MAX_TOKENS = 3000

      def initialize(report:)
        @report = report
        @project = report.project
      end

      def call
        computed = AggregateProjectMetrics.call(
          project: @project,
          period_start: @report.period_start || 90.days.ago.to_date,
          period_end: @report.period_end || Date.current
        )

        sections = ai_sections(computed)
        data = computed.merge(sections).merge(ai_ok: sections.present?)

        @report.update!(
          status: :ready,
          data: data,
          overall_score: sections.dig('overall', 'score'),
          generated_at: Time.current
        )
        Broadcaster.board(@project.workspace_id, 'report_ready', report_id: @report.id, project_id: @project.id)
        @report
      rescue StandardError => e
        Rails.logger.warn("[Reports::GenerateProjectReport] report ##{@report.id}: #{e.class}: #{e.message}")
        @report.update!(status: :failed)
        Broadcaster.board(@project.workspace_id, 'report_failed', report_id: @report.id, project_id: @project.id)
        @report
      end

      private

      def ai_sections(computed)
        builder = Prompts::ProjectAudit.new(
          workspace: @project.workspace,
          client: @project.client,
          project_name: @project.name,
          period_label: period_label,
          metrics_json: JSON.pretty_generate(computed[:kpis].merge(format_breakdown: computed[:format_breakdown])),
          content_json: JSON.pretty_generate(computed[:content]),
          tickets_context: tickets_context
        )
        text = AiAdapter.complete(builder, max_tokens: MAX_TOKENS, operation: 'project_audit', subject: @report)
        parse_json(text)
      end

      # Extract the first {...} JSON object; tolerate accidental prose/fences and
      # the offline stub (returns {} so only the numbers render).
      def parse_json(text)
        raw = text.to_s
        start = raw.index('{')
        finish = raw.rindex('}')
        return {} if start.nil? || finish.nil? || finish <= start

        JSON.parse(raw[start..finish])
      rescue JSON::ParserError => e
        Rails.logger.warn("[Reports::GenerateProjectReport] JSON parse failed: #{e.message}")
        {}
      end

      def tickets_context
        @project.tickets.order(created_at: :desc).first(40).map do |ticket|
          objective = ticket.fields_for('ideation')['objective']
          lessons = strip_html(ticket.fields_for('retrospective')['lessons_learned'])
          parts = ["- [#{ticket.creative_type}] #{ticket.display_title}"]
          parts << "objetivo: #{objective}" if objective.present?
          parts << "retro: #{lessons.truncate(200)}" if lessons.present?
          parts.join(' | ')
        end.join("\n")
      end

      def strip_html(html) = html.to_s.gsub(/<[^>]+>/, ' ').squish

      def period_label
        start = @report.period_start
        finish = @report.period_end
        return '' if start.nil? || finish.nil?

        "#{start.strftime('%d/%m/%Y')} – #{finish.strftime('%d/%m/%Y')}"
      end
    end
  end
end
