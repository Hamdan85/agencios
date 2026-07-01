# frozen_string_literal: true

# A scheduled/published post on one network. Created in `scheduled`, advanced
# through `publishing` → `published` by Operations::Posts::Publish.
class Post < ApplicationRecord
  belongs_to :workspace
  belongs_to :ticket
  belongs_to :social_account
  has_many :post_metrics, dependent: :destroy

  enum :status, { scheduled: 0, publishing: 1, published: 2, failed: 3 }, prefix: true

  scope :due, -> { status_scheduled.where(scheduled_at: ..Time.current) }

  def latest_metric = post_metrics.order(captured_at: :desc).first

  # The creative this post should publish. The team picks it at the posting step
  # (stored as media["creative_id"]); otherwise fall back to the most recent
  # creative that actually has assets attached. This is the single source of
  # truth every vendor's PublishPost reads — never re-derive it ad hoc.
  def publishable_creative
    id = media.is_a?(Hash) ? media["creative_id"] : nil
    (id && ticket.creatives.find_by(id: id)) ||
      ticket.creatives.order(created_at: :desc).detect { |c| c.assets.attached? } ||
      ticket.creatives.order(created_at: :desc).first
  end
end
