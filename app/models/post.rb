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

  def self.ransackable_attributes(_auth = nil)
    %w[id workspace_id ticket_id social_account_id status scheduled_at published_at
       external_post_id permalink failure_reason created_at updated_at]
  end

  def self.ransackable_associations(_auth = nil)
    %w[workspace ticket social_account post_metrics]
  end

  def latest_metric = post_metrics.order(captured_at: :desc).first

  # The creative this post should publish. The team picks it at the posting step
  # (stored as media["creative_id"]); otherwise fall back to the most recent
  # creative that actually has assets attached. This is the single source of
  # truth every vendor's PublishPost reads — never re-derive it ad hoc.
  def publishable_creative
    id = media.is_a?(Hash) ? media['creative_id'] : nil
    (id && ticket.creatives.find_by(id: id)) ||
      ticket.creatives.order(created_at: :desc).detect { |c| c.assets.attached? } ||
      ticket.creatives.order(created_at: :desc).first
  end

  # An optional still image to attach to this post's video as its cover/thumbnail.
  # Set at the posting step (media["cover_creative_id"]) only for thumbnail-capable
  # networks; nil for image/carousel posts. Vendors read this to set the cover.
  def cover_creative
    id = media.is_a?(Hash) ? media['cover_creative_id'] : nil
    id && ticket.creatives.find_by(id: id)
  end
end
