# frozen_string_literal: true

# Shared field readers for the Post serializer family (PostSerializer,
# PostRowSerializer, PostDetailSerializer). Each serializer still picks which
# of these it exposes via its own `attributes` list.
module PostPayload
  def scheduled_at = object.scheduled_at&.iso8601
  def published_at = object.published_at&.iso8601
  def unpublished_at = object.unpublished_at&.iso8601
  def provider = object.social_account&.provider
  def username = object.social_account&.username
  def client_name = object.ticket&.project&.client&.name
  def campaign_name = object.ticket&.project&.name
  def creative_type = object.resolved_creative_type

  # Latest metric snapshot (nil until the first sync).
  def metrics
    m = object.latest_metric
    m && metric_payload(m)
  end

  private

  def metric_payload(metric)
    {
      reach: metric.reach, views: metric.views, likes: metric.likes,
      comments: metric.comments, shares: metric.shares, saves: metric.saves,
      engagement: metric.engagement, captured_at: metric.captured_at&.iso8601
    }
  end
end
