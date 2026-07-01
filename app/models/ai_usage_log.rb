# frozen_string_literal: true

# Unified AI cost ledger — one row per AI vendor call across the platform.
#
# Three providers, two cost shapes:
#   * Anthropic     — token-based (input/output/cache tokens × per-million price)
#   * Google Banana — unit-based  (image count × per-image price)
#   * HeyGen        — unit-based  (video seconds × per-second price)
#
# `Generation.cost_cents` remains the Stripe *billing* meter (what the workspace
# is charged); this table is the internal *cost* trail (what agencios pays its
# AI vendors). Writes go exclusively through Operations::Ai::LogUsage.
class AiUsageLog < ApplicationRecord
  belongs_to :workspace
  belongs_to :user, optional: true
  belongs_to :subject, polymorphic: true, optional: true

  validates :provider, :operation, presence: true

  PROVIDER_ANTHROPIC     = 'anthropic'
  PROVIDER_GOOGLE_BANANA = 'google_banana'
  PROVIDER_HEYGEN        = 'heygen'
  PROVIDERS = [PROVIDER_ANTHROPIC, PROVIDER_GOOGLE_BANANA, PROVIDER_HEYGEN].freeze

  # --- pricing ---------------------------------------------------------------

  # Anthropic price per MILLION tokens, in USD cents, keyed by model prefix
  # (longest-prefix-wins, so order from most specific to least).
  TOKEN_PRICING = {
    'claude-fable' => { input: 1000, output: 5000 },
    'claude-opus' => { input: 500, output: 2500 },
    'claude-3-opus' => { input: 500,  output: 2500 },
    'claude-sonnet' => { input: 300,  output: 1500 },
    'claude-3-5-sonnet' => { input: 300, output: 1500 },
    'claude-3-7-sonnet' => { input: 300, output: 1500 },
    'claude-haiku' => { input: 100, output: 500 },
    'claude-3-5-haiku' => { input: 100, output: 500 }
  }.freeze

  CACHE_READ_FACTOR  = 0.1
  CACHE_WRITE_FACTOR = 1.25
  BATCH_FACTOR       = 0.5

  # Unit-based providers: USD cents per unit. HeyGen varies by engine, so the
  # default is the standard-avatar rate; callers that know the engine pass an
  # explicit cost_cents instead.
  UNIT_PRICING = {
    PROVIDER_GOOGLE_BANANA => { unit_kind: 'image', cents_per_unit: 4.0 }, # ~ $0.039 / image
    PROVIDER_HEYGEN => { unit_kind: 'second', cents_per_unit: 1.667 } # ~ $1.00 / min standard avatar
  }.freeze

  UNIT_TOKEN  = 'token'
  UNIT_IMAGE  = 'image'
  UNIT_SECOND = 'second'

  scope :recent_first, -> { order(created_at: :desc) }
  scope :for_provider, ->(p) { where(provider: p) }

  # --- cost computation ------------------------------------------------------

  def self.token_pricing_for(model)
    TOKEN_PRICING
      .sort_by { |prefix, _| -prefix.length }
      .find { |prefix, _| model.to_s.start_with?(prefix) }&.last
  end

  # Token cost in USD cents (fractional). Returns 0.0 for an unknown model.
  def self.token_cost_cents(model:, input:, output:, cache_write: 0, cache_read: 0, batch: false)
    prices = token_pricing_for(model)
    return 0.0 unless prices

    per_in  = prices[:input]  / 1_000_000.0
    per_out = prices[:output] / 1_000_000.0

    cost = (input.to_i * per_in) +
           (cache_write.to_i * per_in * CACHE_WRITE_FACTOR) +
           (cache_read.to_i  * per_in * CACHE_READ_FACTOR) +
           (output.to_i * per_out)

    batch ? cost * BATCH_FACTOR : cost
  end

  # Unit cost in USD cents (fractional) for image/second providers.
  def self.unit_cost_cents(provider:, units:)
    rate = UNIT_PRICING.dig(provider.to_s, :cents_per_unit)
    return 0.0 unless rate

    units.to_f * rate
  end

  # --- aggregation -----------------------------------------------------------

  # Sum of the stamped cost (cheap; no recomputation).
  def self.total_cost_cents
    sum(:cost_cents)
  end

  def self.cost_by_provider
    group(:provider).sum(:cost_cents)
  end

  def self.cost_by_operation
    group(:operation).sum(:cost_cents)
  end

  def self.cost_by_model
    group(:model).sum(:cost_cents)
  end

  def estimated_cost_usd
    (cost_cents.to_f / 100.0).round(6)
  end

  # --- ActiveAdmin -----------------------------------------------------------

  def self.ransackable_attributes(_auth = nil)
    %w[id workspace_id user_id subject_type subject_id provider operation model
       input_tokens output_tokens cache_creation_input_tokens cache_read_input_tokens
       unit_kind units cost_cents created_at updated_at]
  end

  def self.ransackable_associations(_auth = nil)
    %w[workspace user subject]
  end
end
