# frozen_string_literal: true

# Cron sweep: publishes due posts whose scheduled moment has passed and escalates
# stuck/failed ones. A safety net behind the ticket→published transition.
class MonitorScheduledPostsJob < ApplicationJob
  queue_as :default

  def perform
    Post.status_scheduled.where(scheduled_at: ..Time.current).find_each do |post|
      next if skip_inactive?(post.workspace)

      PublishPostJob.perform_later(post.id)
    end
  end
end
