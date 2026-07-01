# frozen_string_literal: true

class CreateTenancy < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string   :email, null: false
      t.string   :password_digest
      t.string   :name
      t.boolean  :staff, null: false, default: false
      t.string   :google_uid
      t.text     :google_access_token
      t.text     :google_refresh_token
      t.datetime :google_calendar_connected_at
      t.datetime :confirmed_at
      t.timestamps
    end
    add_index :users, 'lower(email)', unique: true, name: 'index_users_on_lower_email'
    add_index :users, :google_uid, unique: true, where: 'google_uid IS NOT NULL'

    create_table :workspaces do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :timezone, null: false, default: 'America/Sao_Paulo'
      t.string :locale, null: false, default: 'pt-BR'
      t.text   :brand_voice
      t.string :default_handle
      t.string :brand_primary_color, default: '#7C3AED'
      t.string :brand_secondary_color, default: '#F59E0B'
      t.timestamps
    end
    add_index :workspaces, :slug, unique: true

    create_table :memberships do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer    :role, null: false, default: 3
      t.timestamps
    end
    add_index :memberships, %i[workspace_id user_id], unique: true

    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :workspace, foreign_key: true
      t.string   :token, null: false
      t.datetime :last_active_at
      t.datetime :expires_at
      t.string   :user_agent
      t.string   :ip_address
      t.timestamps
    end
    add_index :sessions, :token, unique: true

    create_table :settings do |t|
      t.references :workspace, null: false, foreign_key: true, index: { unique: true }
      t.string  :brand_tone
      t.boolean :auto_publish_default, null: false, default: false
      t.text    :google_access_token
      t.text    :google_refresh_token
      t.datetime :google_calendar_connected_at
      t.text    :mercadopago_access_token
      t.string  :mercadopago_user_id
      t.jsonb   :preferences, null: false, default: {}
      t.timestamps
    end

    create_table :subscriptions do |t|
      t.references :workspace, null: false, foreign_key: true, index: { unique: true }
      t.integer  :plan, null: false, default: 0
      t.string   :stripe_customer_id
      t.string   :stripe_subscription_id
      t.string   :status, default: 'trialing'
      t.integer  :seats, null: false, default: 1
      t.datetime :trial_ends_at
      t.datetime :current_period_end
      t.datetime :cancel_at
      t.timestamps
    end
  end
end
