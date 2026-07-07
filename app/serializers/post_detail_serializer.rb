# frozen_string_literal: true

# Full post detail: metadata, the creative to experience, and the whole metric
# history (ascending) that feeds the detail-page trend chart.
class PostDetailSerializer < ActiveModel::Serializer
  include PostPayload

  attributes :id, :status, :scheduled_at, :published_at, :unpublished_at, :caption, :permalink,
             :external_post_id, :provider, :username, :failure_reason, :ticket_id, :ticket_title,
             :client_name, :campaign_name, :campaign_id, :campaign_color, :client_id, :client_logo_url,
             :creative_type, :creative, :metrics, :metric_history

  def client_id = object.ticket&.project&.client_id
  def campaign_id = object.ticket&.project_id
  def campaign_color = object.ticket&.project&.color
  def ticket_title = object.ticket&.display_title
  def client_logo_url = blob_url(object.ticket&.project&.client&.logo)

  def blob_url(attachment)
    return nil unless attachment&.attached?

    Rails.application.routes.url_helpers.rails_blob_url(attachment, host: SystemConfig.app_host)
  rescue StandardError
    nil
  end

  # The creative rendered in CreativeExperience on the detail page.
  def creative
    c = object.publishable_creative
    c && CreativeSerializer.new(c).as_json
  end

  def metric_history
    object.post_metrics.sort_by { |m| m.captured_at || Time.at(0) }.map { |m| metric_payload(m) }
  end
end
