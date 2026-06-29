# frozen_string_literal: true

# The "tag" that groups tickets on the board; `color` drives the card chip.
class Project < ApplicationRecord
  belongs_to :workspace
  belongs_to :client
  has_many :tickets, dependent: :destroy
  has_many :invoice_projects, dependent: :destroy
  has_many :invoices, through: :invoice_projects

  enum :status, { active: 0, paused: 1, archived: 2 }, prefix: true

  validates :name, presence: true
end
