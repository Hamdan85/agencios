# frozen_string_literal: true

# Full-i18n foundation:
# - users.locale        — the UI language of the app user (SPA, personal emails, push)
# - clients.locale      — the UI language of the agency's client (portal, approval, invoices, report PDF)
# - clients.content_language — the language of the client's social-media AUDIENCE; AI-generated
#   content (captions, carousel copy, scripts) follows this, not the UI locale
# - notes/credit_transactions gain key+params columns so system-generated copy is stored as an
#   i18n key rendered at read time (legacy rows keep their rendered PT text as fallback)
class AddI18nColumns < ActiveRecord::Migration[8.1]
  def change
    add_column :users,   :locale, :string, null: false, default: 'pt-BR'
    add_column :clients, :locale, :string, null: false, default: 'pt-BR'
    add_column :clients, :content_language, :string, null: false, default: 'pt-BR'

    add_column :notes, :i18n_key, :string
    add_column :notes, :i18n_params, :jsonb, null: false, default: {}

    add_column :credit_transactions, :description_key, :string
    add_column :credit_transactions, :description_params, :jsonb, null: false, default: {}
  end
end
