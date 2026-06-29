# frozen_string_literal: true

class PurgeExpiredSessionsJob < ApplicationJob
  queue_as :low

  def perform
    Session.where(expires_at: ..Time.current).delete_all
  end
end
