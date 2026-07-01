# frozen_string_literal: true

module Controllers
  module Registrations
    # Registers a user + their first workspace, returning the User. The cookie
    # session lifecycle is an HTTP concern handled by the controller.
    class Create < Base
      def initialize(params:)
        @params = params
      end

      def call
        user, _workspace = Operations::Users::Register.call(
          email: @params.require(:email),
          password: @params.require(:password),
          name: @params[:name],
          workspace_name: @params[:workspace_name]
        )
        user
      end
    end
  end
end
