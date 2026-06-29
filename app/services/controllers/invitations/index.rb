# frozen_string_literal: true

module Controllers
  module Invitations
    # Invitations are table-free signed tokens — there is no pending list to read.
    class Index < Base
      def call
        { invitations: [] }
      end
    end
  end
end
