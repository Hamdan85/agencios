# frozen_string_literal: true

class PostSerializer < ActiveModel::Serializer
  attributes :id, :status, :scheduled_at, :published_at, :caption, :permalink,
             :external_post_id, :provider, :username, :metrics, :ticket_id, :social_account_id

  def scheduled_at = object.scheduled_at&.iso8601
  def published_at = object.published_at&.iso8601
  def provider = object.social_account&.provider
  def username = object.social_account&.username

  def metrics
    m = object.latest_metric
    return nil unless m

    {
      reach: m.reach, views: m.views, likes: m.likes, comments: m.comments,
      shares: m.shares, saves: m.saves, engagement: m.engagement,
      captured_at: m.captured_at&.iso8601
    }
  end
end
