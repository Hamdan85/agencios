# frozen_string_literal: true

# The agency charging its client (Mercado Pago, Pix-first).
class Invoice < ApplicationRecord
  belongs_to :workspace
  belongs_to :client
  has_many :invoice_projects, dependent: :destroy
  has_many :projects, through: :invoice_projects
  has_many :charges, dependent: :destroy

  enum :status, { draft: 0, open: 1, paid: 2, overdue: 3, canceled: 4 }, prefix: true

  def latest_charge = charges.order(created_at: :desc).first
end
