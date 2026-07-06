# frozen_string_literal: true

module Controllers
  module Posts
    # Two modes: nested (ticket_id present) → that ticket's posts (unchanged);
    # global → the workspace's posts with optional filters. Global rows use the
    # richer PostRowSerializer (client/campaign/type/thumbnail).
    class Index < Base
      def initialize(params:)
        @params = params
      end

      def call
        if @params[:ticket_id].present?
          ticket = workspace.tickets.find(@params[:ticket_id])
          return { posts: serialize_collection(ticket.posts.includes(:social_account), PostSerializer) }
        end

        collection_payload(scope, PostRowSerializer, :posts, @params)
      end

      private

      def scope
        rel = Post.for_workspace(workspace)
                  .includes(:post_metrics, :social_account, ticket: { project: :client })
        rel = rel.where(ticket_id: tickets_for_client) if @params[:client_id].present?
        rel = rel.where(ticket_id: Ticket.where(project_id: @params[:project_id])) if @params[:project_id].present?
        rel = rel.joins(:social_account).where(social_accounts: { provider: Array(@params[:providers]) }) if @params[:providers].present?
        rel = rel.where(status: Array(@params[:status])) if @params[:status].present?
        if @params[:creative_types].present?
          rel = rel.joins(ticket: :creatives).where(creatives: { creative_type: Array(@params[:creative_types]) }).distinct
        end
        rel = filter_dates(rel)
        rel = rel.where('posts.caption ILIKE ?', "%#{escape_like(@params[:q])}%") if @params[:q].present?
        rel.order(Arel.sql('COALESCE(posts.published_at, posts.scheduled_at) DESC NULLS LAST'))
      end

      def tickets_for_client
        Ticket.where(project_id: Project.where(client_id: @params[:client_id], workspace_id: workspace.id))
      end

      # Window on the effective date (published else scheduled).
      def filter_dates(rel)
        from = parse_date(@params[:from])
        to = parse_date(@params[:to])
        rel = rel.where('COALESCE(posts.published_at, posts.scheduled_at) >= ?', from.beginning_of_day) if from
        rel = rel.where('COALESCE(posts.published_at, posts.scheduled_at) <= ?', to.end_of_day) if to
        rel
      end

      def parse_date(value)
        value.present? ? Date.parse(value.to_s) : nil
      rescue StandardError
        nil
      end
    end
  end
end
