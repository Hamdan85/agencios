# frozen_string_literal: true

class Client < ApplicationRecord
  belongs_to :workspace
  has_many :projects, dependent: :destroy
  has_many :tickets, through: :projects
  has_many :invoices, dependent: :destroy
  has_many :meetings, dependent: :nullify
  has_many :social_accounts, dependent: :destroy

  # Brand identity (used by creative generation + AI prompts). Visual identity
  # lives in columns + these attachments; voice is `brand_voice`. The workspace
  # carries the agency-level default that these override per client.
  has_one_attached :logo
  has_one_attached :default_creator_avatar
  # Background image for the `image` carousel style (uploaded or copied from a
  # platform creative). Only read when `carousel_style == 'image'`.
  has_one_attached :carousel_background

  enum :status, { active: 0, archived: 1 }, prefix: true

  # Background used when generating branded carousels for this client.
  # `gradient` = the brand-color radial gradient (current default look);
  # `white` = white background with dark text; `image` = a background image
  # (see `carousel_background`). Read by Tickets::CreativeContext.
  enum :carousel_style, { gradient: 'gradient', white: 'white', image: 'image' }, prefix: :carousel

  validates :name, presence: true
  validates :locale, inclusion: { in: ->(_) { I18n.available_locales.map(&:to_s) } }
  # Audience language for AI-generated content — any BCP-47 primary(-region) tag,
  # not limited to the UI locales (a BR agency can run an es-MX client).
  validates :content_language, format: { with: /\A[a-z]{2}(-[A-Z]{2})?\z/ }

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

  # The client's stable, revocable approval-portal secret. Lazily minted; one link
  # per client (not per ticket) — powers /aprovar/:token, which lists this client's
  # tickets awaiting approval.
  def approval_token!
    return approval_token if approval_token.present?

    update!(approval_token: "apv_#{SecureRandom.urlsafe_base64(32)}")
    approval_token
  end

  # Mints a fresh token unconditionally, invalidating any link already shared with
  # the client. Used to rotate a leaked/compromised portal link.
  def rotate_approval_token!
    update!(approval_token: "apv_#{SecureRandom.urlsafe_base64(32)}")
    approval_token
  end

  # The full, shareable portal URL (lazily minting the token on first read).
  def portal_url = "#{SystemConfig.app_host}/portal/#{approval_token!}"

  def revoke_approval_token! = update!(approval_token: nil)

  # The queue shown in the portal: tickets across this client's projects that are
  # awaiting the client's approval, precise (excludes superseded creatives), most
  # recently requested first.
  def pending_approval_tickets
    tickets.awaiting_client_approval
           .includes(:project, :creatives)
           .select(&:pending_client_approval?)
           .sort_by { |t| t.approval_requested_at || Time.at(0) }
           .reverse
  end

  # True when any positioning field has been filled in.
  def positioning? = positioning.present? && positioning.values.any?(&:present?)

  # Symbolized view of the positioning bag for convenient reads.
  def positioning_data = (positioning || {}).symbolize_keys
end
