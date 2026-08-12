# frozen_string_literal: true

module Controllers
  module Webhooks
    module Postgate
      # PostGate pushes post/profile lifecycle and analytics events instead of
      # agencios polling (docs/integrations/postgate.md §5). Verifies
      # X-PostGate-Signature, then dispatches on the event `type`.
      #
      # Returns the HTTP status symbol the controller `head`s:
      #   :unauthorized — bad/stale signature
      #   :ok           — everything else, handled or not (unknown event types
      #                   are logged and acknowledged so PostGate doesn't retry)
      #
      # Each event handler is rescued individually (logged at warn, still :ok) so
      # one bad event never turns into a PostGate retry storm — but a MISSING
      # webhook secret (Vendors::Postgate::Webhook#verify) is a misconfiguration,
      # not a per-event failure, and is left to crash loudly (uncaught, → 500).
      class Receive < Controllers::Base
        def initialize(signature:, payload:)
          @signature = signature
          @payload = payload
        end

        def call
          return :unauthorized unless Vendors::Postgate::Webhook.verify(@payload, @signature)

          dispatch(JSON.parse(@payload))
          :ok
        rescue JSON::ParserError => e
          Rails.logger.warn("[Webhooks::Postgate] invalid JSON payload: #{e.message}")
          :ok
        end

        private

        def dispatch(event)
          type = event['type'].to_s
          data = event['data'] || {}
          handle(type, data)
        rescue StandardError => e
          Rails.logger.warn("[Webhooks::Postgate] #{type} handler failed: #{e.message}")
        end

        def handle(type, data)
          case type
          when 'post.published', 'post.failed', 'post.partial' then handle_post_result(type, data)
          when 'post.insights' then handle_insights(data)
          when 'profile.reauth_required', 'profile.expired' then handle_reauth(data, type)
          when 'profile.disconnected' then handle_disconnected(data)
          when 'profile.stats_updated' then handle_stats_updated(data)
          when 'profile.connected', 'profile.expiring'
            Rails.logger.info("[Webhooks::Postgate] #{type} — no action")
          else
            Rails.logger.info("[Webhooks::Postgate] unhandled event type: #{type}")
          end
        end

        # --- post.published / post.failed / post.partial -------------------------

        def handle_post_result(type, data)
          post = find_post(data)
          return if post.nil? || !post.status_publishing?

          target = extract_target(data)
          if type == 'post.published'
            Operations::Posts::MarkPublished.call(
              post: post, external_post_id: target&.dig('platform_post_id'), permalink: target&.dig('permalink')
            )
          else
            Operations::Posts::MarkPublishFailed.call(post: post, reason: failure_reason(data, target))
          end
        end

        def failure_reason(data, target)
          target&.dig('error_message').presence ||
            data['error'].presence ||
            I18n.t('operations.posts.postgate_webhook_failed')
        end

        # --- post.insights ---------------------------------------------------------

        def handle_insights(data)
          post = find_post(data)
          return if post.nil? || !post.status_published?

          Array(data['targets']).each do |target|
            metrics = target['metrics']
            next if metrics.blank?

            Operations::Posts::RecordMetric.call(post: post, metrics: metric_attrs(metrics, target))
          end
        end

        def metric_attrs(metrics, target)
          {
            reach: metrics['reach'],
            views: metrics['impressions'],
            likes: metrics['likes'],
            comments: metrics['comments'],
            shares: metrics['shares'],
            saves: metrics['saved'],
            raw: target
          }
        end

        # --- profile.reauth_required / profile.expired ----------------------------

        def handle_reauth(data, type)
          account = SocialAccount.find_by(postgate_profile_id: data['profile_id'])
          return if account.nil?

          Operations::Social::FlagNeedsReauth.call(social_account: account, reason: data['reason'] || type)
        end

        # --- profile.disconnected ---------------------------------------------------

        def handle_disconnected(data)
          account = SocialAccount.find_by(postgate_profile_id: data['profile_id'])
          return if account.nil?

          # The remote Profile is already gone (that's what fired this event) —
          # skip the redundant DELETE /api/profiles/{id} call Disconnect would
          # otherwise make.
          Operations::Social::Disconnect.call(account: account, remote: false)
        end

        # --- profile.stats_updated ---------------------------------------------------

        def handle_stats_updated(data)
          account = SocialAccount.find_by(postgate_profile_id: data['profile_id'])
          return if account.nil?

          # Reuses SyncAccountInsights's own write path rather than duplicating
          # the AccountMetric#create! shape here.
          Operations::Social::SyncAccountInsights.call(social_account: account)
        end

        # --- shared lookups ----------------------------------------------------------

        # Post/target payloads may arrive flat (post_id/targets at the top level)
        # or nested under `post` — code defensively for both.
        def find_post(data)
          post_id = data['post_id'] || data.dig('post', 'id')
          return nil if post_id.blank?

          Post.find_by(postgate_post_id: post_id)
        end

        # Our Post is 1:1 with a single PostGate profile/target (one profile per
        # publish, see Vendors::Postgate::Actions::PublishPost#payload).
        def extract_target(data)
          targets = data['targets'] || data.dig('post', 'targets')
          Array(targets).first
        end
      end
    end
  end
end
