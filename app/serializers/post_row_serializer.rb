# frozen_string_literal: true

# Compact row for the posts list. Adds client/campaign/type/thumbnail on top of
# what PostSerializer already exposes.
class PostRowSerializer < ActiveModel::Serializer
  include PostPayload

  attributes :id, :status, :scheduled_at, :published_at, :caption, :permalink,
             :provider, :username, :metrics, :ticket_id,
             :client_name, :campaign_name, :campaign_color, :creative_type, :thumbnail_url

  def thumbnail_url = object.thumbnail_url
  def campaign_color = object.ticket&.project&.color
end
