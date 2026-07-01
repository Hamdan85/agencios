# frozen_string_literal: true

# Unified AI cost ledger. One row per AI vendor call across the platform:
# Anthropic text (token-based), Google Banana images (per-image), HeyGen videos
# (per-second). `Generation` stays the Stripe billing meter; this table is the
# internal cost/audit trail of what agencios pays its AI vendors.
class CreateAiUsageLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_usage_logs do |t|
      t.references :workspace, null: false, foreign_key: true, index: false
      t.references :user, null: true, foreign_key: true

      # Polymorphic owner of the call (ticket / creative / generation), kept as
      # an audit record even if the subject is later deleted (nullable, no FK).
      t.string :subject_type
      t.bigint :subject_id

      t.string :provider, null: false   # anthropic | google_banana | heygen
      t.string :operation, null: false  # summarize_ticket | carousel_copy | ...
      t.string :model                   # token model id / vendor model

      # Token usage (Anthropic). Defaults keep cost math total-safe for non-token
      # providers.
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.integer :cache_creation_input_tokens, null: false, default: 0
      t.integer :cache_read_input_tokens, null: false, default: 0

      # Unit usage (image count / video seconds). `unit_kind` discriminates.
      t.string  :unit_kind # token | image | second
      t.decimal :units, precision: 12, scale: 3, null: false, default: 0

      # Cost stamped at log time (fractional cents, like adv-os) for cheap
      # aggregation; recomputable from PRICING via cost_cents_for.
      t.decimal :cost_cents, precision: 14, scale: 4, null: false, default: 0

      t.timestamps
    end

    add_index :ai_usage_logs, %i[workspace_id created_at]
    add_index :ai_usage_logs, %i[operation created_at]
    add_index :ai_usage_logs, %i[provider created_at]
    add_index :ai_usage_logs, %i[subject_type subject_id]
  end
end
