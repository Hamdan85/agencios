# frozen_string_literal: true

module Controllers
  module Dashboard
    class Index < Base
      STATUS_KEYS = %w[ideation scoping production scheduled published retrospective done].freeze

      def call
        {
          stats: stats,
          tickets_by_status: tickets_by_status,
          upcoming_meetings: serialize_collection(workspace.meetings.upcoming.limit(5), MeetingSerializer),
          recent_generations: recent_generations,
          funnel: tickets_by_status
        }
      end

      private

      def stats
        {
          active_tickets: workspace.tickets.where.not(status: :done).count,
          clients: workspace.clients.count,
          projects: workspace.projects.where(status: :active).count,
          scheduled_posts: workspace.posts.where(status: :scheduled).count,
          open_invoices: workspace.invoices.where(status: :open).count,
          revenue_cents: workspace.invoices.where(status: :paid).sum(:amount_cents)
        }
      end

      def tickets_by_status
        counts = workspace.tickets.group(:status).count
        STATUS_KEYS.index_with { |key| counts[key].to_i }
      end

      def recent_generations
        workspace.generations.order(created_at: :desc).limit(6).map do |generation|
          {
            id: generation.id,
            kind: generation.kind,
            status: generation.status,
            created_at: generation.created_at&.iso8601
          }
        end
      end
    end
  end
end
