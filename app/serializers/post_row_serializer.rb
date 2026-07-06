# frozen_string_literal: true

# Compact row for the posts list. Adds client/campaign/type/thumbnail on top of
# what PostSerializer already exposes.
class PostRowSerializer < ActiveModel::Serializer
  attributes :id, :status, :scheduled_at, :published_at, :caption, :permalink,
             :provider, :username, :metrics, :ticket_id,
             :client_name, :campaign_name, :creative_type, :thumbnail_url

  def scheduled_at = object.scheduled_at&.iso8601
  def published_at = object.published_at&.iso8601
  def provider = object.social_account&.provider
  def username = object.social_account&.username
  def client_name = object.ticket&.project&.client&.name
  def campaign_name = object.ticket&.project&.name
  def creative_type = object.resolved_creative_type
  def thumbnail_url = object.thumbnail_url

  def metrics
    m = object.latest_metric
    return nil unless m

    { reach: m.reach, views: m.views, likes: m.likes, comments: m.comments,
      shares: m.shares, saves: m.saves, engagement: m.engagement, captured_at: m.captured_at&.iso8601 }
  end
end
