# frozen_string_literal: true

# Cron sweep: publishes due posts whose scheduled moment has passed and escalates
# stuck/failed ones. A safety net behind the ticket→published transition.
class MonitorScheduledPostsJob < ApplicationJob
  queue_as :default

  def perform
    # `in_live_project` skips posts of archived campaigns/clients: an archived
    # client is frozen, so its scheduled content must NOT keep going live. The
    # post stays `scheduled` (non-destructive) — reactivate the client to resume.
    Post.status_scheduled.where(scheduled_at: ..Time.current)
        .where(ticket_id: Ticket.in_live_project)
        .find_each do |post|
      next if skip_inactive?(post.workspace)

      PublishPostJob.perform_later(post.id)
    end
  end
end
