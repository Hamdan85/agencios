# frozen_string_literal: true

module Api
  module V1
    class RegistrationsController < BaseController
      allow_unauthenticated_access

      def create
        user = Controllers::Registrations::Create.call(params:)

        # Cookie/session lifecycle is an HTTP concern owned by the controller.
        start_new_session_for(user)
        Current.workspace = nil # force re-resolution against the new membership
        resume_session

        render_created(Controllers::Me::Show.call(include_membership: false))
      end
    end
  end
end
