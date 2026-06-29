# frozen_string_literal: true

class InvoiceProject < ApplicationRecord
  belongs_to :invoice
  belongs_to :project
end
