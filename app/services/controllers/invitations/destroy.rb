# frozen_string_literal: true

module Controllers
  module Invitations
    # Signed-token invites carry no server state, so there is nothing to revoke.
    class Destroy < Base
      def call
        require_manager!
        { message: I18n.t('api.invitations.canceled') }
      end
    end
  end
end
