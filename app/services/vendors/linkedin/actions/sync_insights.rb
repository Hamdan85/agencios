# frozen_string_literal: true

module Vendors
  module Linkedin
    module Actions
      # Uniform seam entrypoint: fetch analytics for a published LinkedIn post.
      #
      # LinkedIn analytics are ORGANIZATION-ONLY — there is no member-profile post
      # analytics API. For member posts we return all-zeros with a `raw` note. For
      # org posts we pull per-share statistics and map them to the uniform schema.
      #
      # Returns { reach:, views:, likes:, comments:, shares:, saves:, raw: }.
      # See docs/integrations/linkedin.md §7.
      class SyncInsights
        def self.call(...) = new(...).call

        def initialize(post)
          @post = post
          @social_account = post.social_account
        end

        def call
          org_urn = @social_account.default_org_urn.presence
          share_urn = @post.external_post_id.presence

          # Member-only posts have no analytics endpoint at all.
          return unavailable('member_profile_analytics_unsupported') if org_urn.blank?
          return unavailable('missing_share_urn') if share_urn.blank?

          stats = Vendors::Linkedin::Actions::FetchPostStatistics.call(
            social_account: @social_account, org_urn: org_urn, share_urn: share_urn
          )
          map_metrics(stats)
        rescue Vendors::Base::AuthenticationError => e
          # Org analytics require partner approval (rw_organization_admin).
          unavailable('analytics_not_authorized', detail: e.message)
        end

        private

        def map_metrics(stats)
          {
            reach: stats['uniqueImpressionsCount'].to_i,
            views: stats['impressionCount'].to_i,
            likes: stats['likeCount'].to_i,
            comments: stats['commentCount'].to_i,
            shares: stats['shareCount'].to_i,
            saves: 0, # LinkedIn has no "save" metric
            raw: stats
          }
        end

        def unavailable(reason, detail: nil)
          {
            reach: 0, views: 0, likes: 0, comments: 0, shares: 0, saves: 0,
            raw: { 'unavailable' => reason, 'detail' => detail }.compact
          }
        end
      end
    end
  end
end
