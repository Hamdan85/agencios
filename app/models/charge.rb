# frozen_string_literal: true

# A single Mercado Pago payment attempt for an invoice. Status is authoritative
# only after a GET /v1/payments/{id} reconciliation.
class Charge < ApplicationRecord
  belongs_to :workspace
  belongs_to :invoice

  enum :method, { pix: 0, boleto: 1, card: 2 }, prefix: true

  def pix? = method_pix?
  def paid? = status == 'approved'
end
