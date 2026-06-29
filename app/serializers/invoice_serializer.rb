# frozen_string_literal: true

class InvoiceSerializer < ActiveModel::Serializer
  attributes :id, :status, :amount_cents, :currency, :description, :due_date,
             :external_reference, :client_id, :client_name, :project_ids,
             :charge, :created_at

  def due_date = object.due_date&.iso8601
  def client_name = object.client&.name
  def project_ids = object.projects.pluck(:id)
  def created_at = object.created_at&.iso8601

  def charge
    charge = object.latest_charge
    return nil unless charge

    {
      id: charge.id,
      provider: charge.provider,
      method: charge.method,
      status: charge.status,
      paid: charge.paid?,
      payment_link: charge.payment_link,
      pix_qr_code: charge.pix_qr_code,
      pix_qr_code_base64: charge.pix_qr_code_base64,
      ticket_url: charge.ticket_url,
      amount_cents: charge.amount_cents
    }
  end
end
