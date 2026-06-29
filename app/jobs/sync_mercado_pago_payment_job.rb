# frozen_string_literal: true

class SyncMercadoPagoPaymentJob < ApplicationJob
  queue_as :critical

  def perform(payment_id)
    workspace = Charge.find_by(mp_payment_id: payment_id.to_s)&.workspace
    Operations::Billing::SyncPaymentStatus.call(payment_id: payment_id.to_s, workspace: workspace)
  end
end
