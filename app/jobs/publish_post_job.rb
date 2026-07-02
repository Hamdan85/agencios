# frozen_string_literal: true

class PublishPostJob < ApplicationJob
  queue_as :critical

  # Transient vendor errors retry SILENTLY (the post stays `publishing`, no alert,
  # no failure email). The user is only alarmed once the failure is final:
  #   - a transient error whose retries are all exhausted → retry_on's block, or
  #   - a permanent error → the rescue in #perform, immediately (no retry).
  # Operations::Posts::MarkPublishFailed owns that terminal path in both cases.
  retry_on Vendors::Base::RateLimitError, Vendors::Base::ServerError,
           wait: :polynomially_longer, attempts: 4 do |job, error|
    post = Post.find_by(id: job.arguments.first)
    Operations::Posts::MarkPublishFailed.call(post: post, reason: error.message) if post
  end

  def perform(post_id)
    post = Post.find_by(id: post_id)
    return unless post
    return if skip_inactive?(post.workspace)

    Operations::Posts::Publish.call(post: post)
  rescue Vendors::Base::RateLimitError, Vendors::Base::ServerError
    raise # transient — let retry_on retry silently and alarm only when exhausted
  rescue StandardError => e
    # Permanent failure: alarm now, and do NOT re-raise so Sidekiq's default retry
    # can't silently re-run it and re-alarm on every pass.
    Operations::Posts::MarkPublishFailed.call(post: post, reason: e.message)
  end
end
