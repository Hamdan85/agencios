# frozen_string_literal: true

class CreateClientBilling < ActiveRecord::Migration[8.1]
  def change
    create_table :invoices do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true
      t.integer  :status, null: false, default: 0
      t.integer  :amount_cents, null: false, default: 0
      t.string   :currency, null: false, default: 'BRL'
      t.text     :description
      t.date     :due_date
      t.string   :external_reference
      t.timestamps
    end
    add_index :invoices, %i[workspace_id status]
    add_index :invoices, :external_reference, unique: true, where: 'external_reference IS NOT NULL'

    create_table :invoice_projects do |t|
      t.references :invoice, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.timestamps
    end
    add_index :invoice_projects, %i[invoice_id project_id], unique: true

    create_table :charges do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :invoice, null: false, foreign_key: true
      t.string   :mp_payment_id
      t.integer  :method, null: false, default: 0
      t.string   :status, default: 'pending'
      t.integer  :amount_cents, null: false, default: 0
      t.text     :pix_qr_code
      t.text     :pix_qr_code_base64
      t.string   :ticket_url
      t.datetime :expires_at
      t.timestamps
    end
    add_index :charges, :mp_payment_id, unique: true, where: 'mp_payment_id IS NOT NULL'
  end
end
