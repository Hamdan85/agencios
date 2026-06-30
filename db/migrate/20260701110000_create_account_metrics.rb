# frozen_string_literal: true

# A dated snapshot of one social account's PROFILE-level analytics (the account
# vanity numbers an audit deck opens with: followers, reach, story replies, …),
# mirroring PostMetric but at the account rather than the post level. Period
# deltas (e.g. "−31.7% accounts reached") are computed by comparing consecutive
# snapshots, so this table accrues the history those trends depend on.
class CreateAccountMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :account_metrics do |t|
      t.references :social_account, null: false, foreign_key: true
      t.references :workspace, null: false, foreign_key: true, index: false

      t.datetime :captured_at, null: false
      # The window these aggregate counters cover (insights are period-bound;
      # `followers`/`profile snapshot` are point-in-time at captured_at).
      t.date :period_start
      t.date :period_end

      t.integer :followers,        default: 0, null: false # point-in-time total
      t.integer :new_followers,    default: 0, null: false # follower delta over the window
      t.integer :accounts_reached, default: 0, null: false
      t.integer :profile_views,    default: 0, null: false
      t.integer :views,            default: 0, null: false # content views over the window
      t.integer :story_replies,    default: 0, null: false
      t.integer :total_interactions, default: 0, null: false

      t.jsonb :raw, default: {}, null: false

      t.timestamps
    end

    add_index :account_metrics, %i[social_account_id captured_at]
    add_index :account_metrics, %i[workspace_id captured_at]
  end
end
