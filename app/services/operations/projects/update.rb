# frozen_string_literal: true

module Operations
  module Projects
    # Updates a project's own metadata. Used by the HTTP layer and by the AI
    # strategy planner (the `update_project` tool). Only whitelisted attributes
    # are applied; blank date strings clear the date.
    class Update < Operations::Base
      PERMITTED = %i[name description color status starts_on ends_on budget_cents].freeze

      def initialize(project:, attributes:)
        @project = project
        @attributes = normalize(attributes)
      end

      def call
        @project.update!(@attributes) if @attributes.present?
        @project
      end

      private

      # Accept string- or symbol-keyed hashes (the tool sends strings); keep only
      # permitted keys and coerce "" dates to nil.
      def normalize(attributes)
        (attributes || {}).to_h.symbolize_keys.slice(*PERMITTED).each_with_object({}) do |(key, value), acc|
          acc[key] = %i[starts_on ends_on].include?(key) ? value.presence : value
        end
      end
    end
  end
end
