# frozen_string_literal: true

class Client < ApplicationRecord
  belongs_to :workspace
  has_many :projects, dependent: :destroy
  has_many :invoices, dependent: :destroy
  has_many :meetings, dependent: :nullify
  has_many :social_accounts, dependent: :destroy

  # Brand identity (used by creative generation + AI prompts). Visual identity
  # lives in columns + these attachments; voice is `brand_voice`. The workspace
  # carries the agency-level default that these override per client.
  has_one_attached :logo
  has_one_attached :default_creator_avatar

  enum :status, { active: 0, archived: 1 }, prefix: true

  validates :name, presence: true

  # Brand-positioning framework captured by the creation wizard. Stored in the
  # `positioning` jsonb bag and threaded into every AI prompt for tickets under
  # this client (via Prompts::Base#positioning_block). `content_pillars` is an
  # array; the rest are free text. `statement` is the AI-synthesized one-paragraph
  # positioning statement. Brand voice is NOT here — it is the `brand_voice` column.
  POSITIONING_KEYS = %w[
    one_liner category mission target_audience audience_pain value_proposition
    differentiators competitors content_pillars keywords guardrails
    statement
  ].freeze

  ARRAY_POSITIONING_KEYS = %w[content_pillars].freeze

  # Keeps only known keys; trims strings and drops blanks. Pure helper used by the
  # operations that write positioning, so the jsonb never accumulates junk keys.
  def self.sanitize_positioning(raw)
    return {} if raw.blank?

    raw.to_h.stringify_keys.slice(*POSITIONING_KEYS).each_with_object({}) do |(key, value), acc|
      cleaned =
        if ARRAY_POSITIONING_KEYS.include?(key)
          Array(value).map { |v| v.to_s.strip }.reject(&:blank?)
        else
          value.to_s.strip
        end
      acc[key] = cleaned if cleaned.present?
    end
  end

  # True when any positioning field has been filled in.
  def positioning? = positioning.present? && positioning.values.any?(&:present?)

  # Symbolized view of the positioning bag for convenient reads.
  def positioning_data = (positioning || {}).symbolize_keys
end
