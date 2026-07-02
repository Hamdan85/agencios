# frozen_string_literal: true

module Operations
  module Subtasks
    # Mutate a subtask's attributes (title, done, due_date, position, assignee).
    # The single domain entry point for changing a subtask, so callers (operations,
    # jobs) never bare-update! another entity from inside their own service.
    class Update < Operations::Base
      PERMITTED = %i[title done due_date position assignee_id estimate_hours].freeze

      def initialize(subtask, **attributes)
        @subtask = subtask
        @attributes = attributes.slice(*PERMITTED)
      end

      def call
        @subtask.update!(@attributes) if @attributes.any?
        @subtask
      end
    end
  end
end
