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
end
