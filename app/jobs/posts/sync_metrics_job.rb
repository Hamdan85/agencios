# frozen_string_literal: true

module Posts
  # Syncs analytics for recently published posts. Runs on a cron (denser early,
  # then daily). With a post_id, syncs just that post.
  class SyncMetricsJob < ApplicationJob
    queue_as :media

    def perform(post_id = nil)
      if post_id
        post = Post.find_by(id: post_id)
        Operations::Posts::SyncMetrics.call(post: post) if post
        return
      end

      Post.status_published.where(published_at: 30.days.ago..).find_each do |post|
        next if skip_inactive?(post.workspace)

        Operations::Posts::SyncMetrics.call(post: post)
      rescue StandardError => e
        Rails.logger.warn("[Posts::SyncMetricsJob] post ##{post.id}: #{e.message}")
      end
    end
  end
end
