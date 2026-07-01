# frozen_string_literal: true

module Operations
  module Reports
    # Pure computation: walks a project's published posts + the client's account
    # snapshots over a window and returns the quantitative block of the audit
    # report (the "OS NÚMEROS" tiles + the per-content performance table). This is
    # both persisted in the report and fed to the AI prompt as ground truth.
    #
    # No side effects. Returns a Hash with symbol keys.
    class AggregateProjectMetrics < Operations::Base
      # Ticket creative types that count as Reels/short-video for the deck's
      # "compartilhamentos de Reels" tile and format breakdown.
      REEL_TYPES = %w[reel ugc_video].freeze
      POST_METRIC_KEYS = %i[reach views likes comments shares saves].freeze

      def initialize(project:, period_start:, period_end:)
        @project = project
        @period_start = period_start.to_date
        @period_end = period_end.to_date
      end

      def call
        {
          period: period_block,
          kpis: kpis,
          content: content_performance,
          totals: post_totals,
          format_breakdown: format_breakdown
        }
      end

      private

      def range = @period_start.beginning_of_day..@period_end.end_of_day

      def posts
        @posts ||= Post.where(ticket_id: @project.tickets.select(:id))
                       .status_published
                       .where(published_at: range)
                       .includes(:post_metrics, :social_account, :ticket)
                       .to_a
      end

      # The latest metric snapshot for each post, as a parallel array (nil-safe).
      def latest_for(post) = post.post_metrics.max_by { |m| m.captured_at || Time.at(0) }

      def post_totals
        totals = POST_METRIC_KEYS.index_with { 0 }
        posts.each do |post|
          metric = latest_for(post)
          next unless metric

          POST_METRIC_KEYS.each { |k| totals[k] += metric.public_send(k).to_i }
        end
        totals[:engagement] = totals[:likes] + totals[:comments] + totals[:shares] + totals[:saves]
        totals[:posts_count] = posts.size
        totals
      end

      # Shares attributable to Reel-type content only (the deck's headline tile).
      def reel_shares
        posts.sum do |post|
          next 0 unless REEL_TYPES.include?(post.ticket&.creative_type)

          latest_for(post)&.shares.to_i
        end
      end

      # One entry per published post, richest-first by views. Feeds slide 4
      # (formats that work / don't) and the AI's qualitative read.
      def content_performance
        posts.filter_map do |post|
          metric = latest_for(post)
          next unless metric

          {
            label: post.ticket&.display_title,
            creative_type: post.ticket&.creative_type,
            channel: post.social_account&.provider,
            views: metric.views.to_i,
            reach: metric.reach.to_i,
            shares: metric.shares.to_i,
            saves: metric.saves.to_i,
            engagement: metric.engagement,
            permalink: post.permalink,
            published_at: post.published_at&.iso8601
          }
        end.sort_by { |c| -c[:views] }.first(20)
      end

      # Aggregate views/shares per creative type — the structural pattern behind
      # "which formats perform".
      def format_breakdown
        groups = content_performance.group_by { |c| c[:creative_type].presence || 'outros' }
        groups.map do |type, entries|
          {
            creative_type: type,
            count: entries.size,
            views: entries.sum { |e| e[:views] },
            shares: entries.sum { |e| e[:shares] },
            avg_views: (entries.sum { |e| e[:views] } / entries.size.to_f).round
          }
        end.sort_by { |g| -g[:views] }
      end

      def kpis
        totals = post_totals
        current = account_snapshot(@period_end.end_of_day)
        prior = account_snapshot((@period_end - window_days).end_of_day)

        {
          followers: current&.dig(:followers),
          new_followers: current&.dig(:new_followers),
          accounts_reached: current&.dig(:accounts_reached),
          story_replies: current&.dig(:story_replies),
          profile_views: current&.dig(:profile_views),
          views: totals[:views],
          reach: totals[:reach],
          reel_shares: reel_shares,
          engagement: totals[:engagement],
          posts_count: totals[:posts_count],
          follower_growth_pct: pct_delta(current&.dig(:followers), prior&.dig(:followers)),
          reach_delta_pct: pct_delta(current&.dig(:accounts_reached), prior&.dig(:accounts_reached)),
          has_account_data: !current.nil?
        }
      end

      # Sum of the latest account snapshot (at or before `as_of`) across every
      # connected account on the client. Returns nil when no history exists.
      def account_snapshot(as_of)
        metrics = connected_accounts.filter_map { |a| a.account_metrics.as_of(as_of).first }
        return nil if metrics.empty?

        %i[followers new_followers accounts_reached profile_views story_replies views total_interactions]
          .index_with { |field| metrics.sum { |m| m.public_send(field).to_i } }
      end

      def connected_accounts
        @connected_accounts ||= @project.client.social_accounts.status_connected.to_a
      end

      def window_days = (@period_end - @period_start).to_i.clamp(1, 365)

      def pct_delta(current, prior)
        return nil if current.nil? || prior.nil? || prior.zero?

        (((current - prior) / prior.to_f) * 100).round(1)
      end

      def period_block
        {
          start: @period_start.iso8601,
          end: @period_end.iso8601,
          days: window_days
        }
      end
    end
  end
end
