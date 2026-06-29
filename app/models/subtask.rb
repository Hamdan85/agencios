# frozen_string_literal: true

class Subtask < ApplicationRecord
  belongs_to :workspace
  belongs_to :ticket
  belongs_to :assignee, class_name: "User", optional: true

  validates :title, presence: true

  scope :open, -> { where(done: false) }
  scope :ordered, -> { order(:position, :created_at) }
end
