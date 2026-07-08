# frozen_string_literal: true

module Operations
  module Projects
    # Creates a Project on the active workspace (the aggregate root itself).
    class Create < Operations::Base
      PERMITTED = %i[client_id name description color status starts_on ends_on budget_cents settings].freeze

      def initialize(params)
        @params = params.to_h.symbolize_keys.slice(*PERMITTED)
      end

      def call
        find_active_client!(@params[:client_id])
        project = workspace.projects.new(@params)
        project.save!
        project
      end
    end
  end
end
