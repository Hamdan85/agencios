# frozen_string_literal: true

# A charge now carries a hosted payment link (e.g. Mercado Pago Checkout Pro
# `init_point`) generated on demand, and a `provider` so other gateways
# (Asaas, Stripe, Stone, …) can slot in later. Pix-QR columns stay for the
# direct-Pix path.
class AddPaymentLinkToCharges < ActiveRecord::Migration[8.1]
  def change
    change_table :charges, bulk: true do |t|
      t.string :provider, null: false, default: "mercado_pago"
      t.text   :payment_link
      t.string :preference_id
    end
  end
end
