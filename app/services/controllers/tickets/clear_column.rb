# frozen_string_literal: true

module Controllers
  module Tickets
    # POST /api/v1/tickets/clear_column { status }
    # Archives every active ticket in the given column. Managers only.
    class ClearColumn < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        Operations::Tickets::ClearColumn.call(
          workspace, @params.require(:status), user: user
        )
      end
    end
  end
end
