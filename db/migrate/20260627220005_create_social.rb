# frozen_string_literal: true

class CreateSocial < ActiveRecord::Migration[8.1]
  def change
    create_table :social_accounts do |t|
      t.references :workspace, null: false, foreign_key: true
      t.integer  :provider, null: false
      t.string   :external_user_id
      t.string   :username
      t.string   :page_id
      t.string   :ig_user_id
      t.string   :channel_id
      t.string   :member_urn
      t.string   :default_org_urn
      t.text     :user_access_token
      t.text     :page_access_token
      t.text     :refresh_token
      t.datetime :token_expires_at
      t.jsonb    :scopes, null: false, default: []
      t.integer  :status, null: false, default: 0
      t.datetime :last_synced_at
      t.timestamps
    end
    add_index :social_accounts, %i[workspace_id provider]

    create_table :posts do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :ticket, null: false, foreign_key: true
      t.references :social_account, null: false, foreign_key: true
      t.integer  :status, null: false, default: 0
      t.datetime :scheduled_at
      t.datetime :published_at
      t.text     :caption
      t.string   :external_post_id
      t.string   :permalink
      t.jsonb    :media, null: false, default: {}
      t.string   :failure_reason
      t.timestamps
    end
    add_index :posts, %i[workspace_id status]
    add_index :posts, %i[workspace_id scheduled_at]

    create_table :post_metrics do |t|
      t.references :post, null: false, foreign_key: true
      t.datetime :captured_at, null: false
      t.integer  :reach, default: 0
      t.integer  :views, default: 0
      t.integer  :likes, default: 0
      t.integer  :comments, default: 0
      t.integer  :shares, default: 0
      t.integer  :saves, default: 0
      t.jsonb    :raw, null: false, default: {}
      t.timestamps
    end
    add_index :post_metrics, %i[post_id captured_at]
  end
end
