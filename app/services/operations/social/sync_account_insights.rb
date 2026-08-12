# frozen_string_literal: true

module Operations
  module Social
    # Pulls profile-level analytics for one connected account and upserts a dated
    # AccountMetric snapshot. Driven by Social::SyncAccountInsightsJob (cron).
    # A postgate-sourced account (any provider) always routes through PostGate's
    # own account-insights action; a direct account only contributes when its
    # provider has one wired below — others are skipped.
    class SyncAccountInsights < Operations::Base
      # Per-provider account-insights action for DIRECT accounts (uniform return
      # shape). Add providers here as their account-level analytics are wired.
      ACTIONS = {
        'instagram' => 'Vendors::Meta::Actions::SyncAccountInsights'
      }.freeze

      def initialize(social_account:, window: 30.days)
        @social_account = social_account
        @window = window
      end

      def call
        action = resolve_action
        return nil unless action

        now = Time.current
        m = action.call(@social_account, since: now - @window, until_time: now) || {}

        @social_account.account_metrics.create!(
          workspace: @social_account.workspace,
          captured_at: now,
          period_start: (now - @window).to_date,
          period_end: now.to_date,
          followers: m[:followers].to_i,
          new_followers: m[:new_followers].to_i,
          accounts_reached: m[:accounts_reached].to_i,
          profile_views: m[:profile_views].to_i,
          views: m[:views].to_i,
          story_replies: m[:story_replies].to_i,
          total_interactions: m[:total_interactions].to_i,
          raw: m[:raw] || {}
        )
      end

      private

      def resolve_action
        return Vendors::Postgate::Actions::SyncAccountInsights if @social_account.connection_source_postgate?

        ACTIONS[@social_account.provider]&.constantize
      end
    end
  end
end
