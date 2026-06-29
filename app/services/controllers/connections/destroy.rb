# frozen_string_literal: true

module Controllers
  module Connections
    # Revoke a user's authorization for one external application: revokes every
    # active access token they hold for it (so Claude loses access immediately).
    class Destroy < Base
      def initialize(params:)
        @params = params
      end

      def call
        tokens = Doorkeeper::AccessToken.where(
          resource_owner_id: user.id, application_id: @params[:id], revoked_at: nil
        )
        tokens.each(&:revoke)
        { revoked: tokens.size }
      end
    end
  end
end
