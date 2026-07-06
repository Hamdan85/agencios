# frozen_string_literal: true

module Operations
  module Analytics
    # Workspace-scoped, filterable aggregation over published posts — the analytics
    # header of the posts hub. Generalizes Operations::Reports::AggregateProjectMetrics
    # from a single project/window to the whole workspace with optional filters.
    # Pure: no side effects. Sums the latest PostMetric per post.
    class PostsOverview < Operations::Base
      METRIC_KEYS = %i[reach views likes comments shares saves].freeze

      def initialize(workspace:, filters: {})
        @workspace = workspace
        @filters = filters || {}
      end

      def call
        {
          period: { from: from.iso8601, to: to.iso8601 },
          kpis: kpis,
          timeseries: timeseries,
          by_network: by { |p| provider_of(p) }.map { |k, v| v.merge(provider: k) }.sort_by { |h| -h[:views] },
          by_type: by { |p| type_of(p) }.map { |k, v| v.merge(creative_type: k) }.sort_by { |h| -h[:views] },
          by_campaign: by { |p| campaign_of(p) }.map { |k, v| v.merge(campaign: k) }.sort_by { |h| -h[:views] },
          top_posts: top_posts
        }
      end

      private

      def from = @from ||= parse(@filters[:from]) || 30.days.ago.to_date
      def to   = @to ||= parse(@filters[:to]) || Date.current

      def posts
        @posts ||= begin
          rel = Post.for_workspace(@workspace).status_published
                    .where(published_at: from.beginning_of_day..to.end_of_day)
                    .includes(:post_metrics, :social_account, ticket: { project: :client })
          rel = rel.where(ticket_id: Ticket.where(project_id: Project.where(client_id: @filters[:client_id]))) if @filters[:client_id].present?
          rel = rel.where(ticket_id: Ticket.where(project_id: @filters[:project_id])) if @filters[:project_id].present?
          rel = rel.joins(:social_account).where(social_accounts: { provider: Array(@filters[:providers]) }) if @filters[:providers].present?
          rel.to_a
        end
      end

      def latest_for(post) = post.post_metrics.max_by { |m| m.captured_at || Time.at(0) }

      def kpis
        totals = METRIC_KEYS.index_with { 0 }
        posts.each do |post|
          m = latest_for(post)
          next unless m

          METRIC_KEYS.each { |k| totals[k] += m.public_send(k).to_i }
        end
        totals[:engagement] = totals[:likes] + totals[:comments] + totals[:shares] + totals[:saves]
        totals[:posts_count] = posts.size
        totals
      end

      def timeseries
        posts.group_by { |p| p.published_at&.to_date }.compact.sort.map do |date, group|
          agg = group.sum { |p| latest_for(p)&.views.to_i }
          eng = group.sum { |p| latest_for(p)&.engagement.to_i }
          reach = group.sum { |p| latest_for(p)&.reach.to_i }
          { date: date.iso8601, views: agg, engagement: eng, reach: reach }
        end
      end

      def by(&group_key)
        posts.each_with_object(Hash.new { |h, k| h[k] = { posts_count: 0, views: 0, reach: 0, engagement: 0 } }) do |post, acc|
          key = group_key.call(post) || 'outros'
          m = latest_for(post)
          acc[key][:posts_count] += 1
          next unless m

          acc[key][:views] += m.views.to_i
          acc[key][:reach] += m.reach.to_i
          acc[key][:engagement] += m.engagement.to_i
        end
      end

      def top_posts
        posts.filter_map do |post|
          m = latest_for(post)
          next unless m

          { post_id: post.id, label: post.ticket&.display_title, provider: provider_of(post),
            creative_type: type_of(post), campaign: campaign_of(post),
            published_at: post.published_at&.iso8601, views: m.views.to_i, engagement: m.engagement,
            permalink: post.permalink }
        end.sort_by { |c| -c[:views] }.first(20)
      end

      def provider_of(post) = post.social_account&.provider
      def type_of(post) = post.resolved_creative_type
      def campaign_of(post) = post.ticket&.project&.name

      def parse(value)
        value.present? ? Date.parse(value.to_s) : nil
      rescue StandardError
        nil
      end
    end
  end
end
