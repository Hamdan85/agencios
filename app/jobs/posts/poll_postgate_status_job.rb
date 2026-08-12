# frozen_string_literal: true

module Posts
  # Polls PostGate for a post's delivery outcome after Operations::Posts::Publish
  # got back `pending: true` (PostGate accepted the post but hadn't confirmed the
  # target published within the synchronous poll window). Growing backoff: 10s,
  # 30s, 1m, 2m, 5m, 10m, then every 15m, up to ~2 hours total before giving up.
  #
  # Idempotent both ways: a webhook may finalize the post before (or while) this
  # job runs, and this job may finalize it before the webhook arrives — whichever
  # gets there first wins, the other is a no-op (guarded by `status_publishing?`
  # here, and by Operations::Posts::MarkPublished/MarkPublishFailed themselves).
  class PollPostgateStatusJob < ApplicationJob
    queue_as :default

    WAIT_SCHEDULE = [10.seconds, 30.seconds, 1.minute, 2.minutes, 5.minutes, 10.minutes].freeze
    STEADY_WAIT = 15.minutes
    TIMEOUT = 2.hours

    def perform(post_id, attempt = 1)
      post = Post.find_by(id: post_id)
      return unless post
      return unless post.status_publishing?
      return if post.postgate_post_id.blank?

      pg_post = Vendors::Postgate::Client.new.get_post(post.postgate_post_id)
      target = Array(pg_post['targets']).first

      if target && target['status'] == 'published'
        Operations::Posts::MarkPublished.call(
          post: post, external_post_id: target['platform_post_id'], permalink: target['permalink']
        )
      elsif target && %w[failed skipped].include?(target['status'])
        Operations::Posts::MarkPublishFailed.call(
          post: post, reason: target['error_message'].presence || "PostGate target #{target['status']}"
        )
      elsif %w[failed canceled].include?(pg_post['status'])
        Operations::Posts::MarkPublishFailed.call(post: post, reason: "PostGate post #{pg_post['status']}")
      else
        reschedule(post, attempt)
      end
    rescue Vendors::Base::Error => e
      # Transient vendor error while polling — keep polling (it still counts
      # toward the attempt/timeout budget) rather than failing a post that may
      # still be about to succeed.
      Rails.logger.warn("[Posts::PollPostgateStatusJob] post ##{post_id} attempt #{attempt}: #{e.message}")
      reschedule(post, attempt)
    end

    private

    def reschedule(post, attempt)
      next_attempt = attempt + 1
      if elapsed_through(next_attempt) >= TIMEOUT
        Operations::Posts::MarkPublishFailed.call(
          post: post, reason: I18n.t('operations.posts.postgate_poll_timeout')
        )
        return
      end

      self.class.set(wait: next_wait(next_attempt)).perform_later(post.id, next_attempt)
    end

    # The wait BEFORE attempt `n`'s job runs.
    def next_wait(attempt)
      WAIT_SCHEDULE[attempt - 1] || STEADY_WAIT
    end

    # Total elapsed time once attempt `n`'s job has run.
    def elapsed_through(attempt)
      (1..attempt).sum { |a| next_wait(a) }
    end
  end
end
