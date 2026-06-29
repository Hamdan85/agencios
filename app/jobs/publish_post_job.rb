# frozen_string_literal: true

class PublishPostJob < ApplicationJob
  queue_as :critical

  # Transient vendor errors retry; permanent ones surface as a failed Post (the
  # operation records the failure + note before re-raising).
  retry_on Vendors::Base::RateLimitError, Vendors::Base::ServerError,
           wait: :polynomially_longer, attempts: 4

  def perform(post_id)
    post = Post.find_by(id: post_id)
    return unless post
    return if skip_inactive?(post.workspace)

    Operations::Posts::Publish.call(post: post)
  end
end
