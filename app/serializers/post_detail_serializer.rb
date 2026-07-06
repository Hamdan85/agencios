# frozen_string_literal: true

# Full post detail: metadata, the creative to experience, and the whole metric
# history (ascending) that feeds the detail-page trend chart.
class PostDetailSerializer < ActiveModel::Serializer
  attributes :id, :status, :scheduled_at, :published_at, :unpublished_at, :caption, :permalink,
             :external_post_id, :provider, :username, :failure_reason, :ticket_id,
             :client_name, :campaign_name, :campaign_id, :client_id, :creative_type,
             :creative, :metrics, :metric_history

  def scheduled_at = object.scheduled_at&.iso8601
  def published_at = object.published_at&.iso8601
  def unpublished_at = object.unpublished_at&.iso8601
  def provider = object.social_account&.provider
  def username = object.social_account&.username
  def client_name = object.ticket&.project&.client&.name
  def client_id = object.ticket&.project&.client_id
  def campaign_name = object.ticket&.project&.name
  def campaign_id = object.ticket&.project_id
  def creative_type = object.resolved_creative_type

  # The creative rendered in CreativeExperience on the detail page.
  def creative
    c = object.publishable_creative
    c && CreativeSerializer.new(c).as_json
  end

  def metrics
    m = object.latest_metric
    return nil unless m

    { reach: m.reach, views: m.views, likes: m.likes, comments: m.comments,
      shares: m.shares, saves: m.saves, engagement: m.engagement, captured_at: m.captured_at&.iso8601 }
  end

  def metric_history
    object.post_metrics.sort_by { |m| m.captured_at || Time.at(0) }.map do |m|
      { captured_at: m.captured_at&.iso8601, reach: m.reach, views: m.views, likes: m.likes,
        comments: m.comments, shares: m.shares, saves: m.saves, engagement: m.engagement }
    end
  end
end
