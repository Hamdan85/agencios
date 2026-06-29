# frozen_string_literal: true

module Api
  module V1
    class PasswordResetsController < BaseController
      allow_unauthenticated_access

      def create = render_ok(Controllers::PasswordResets::Create.call(params:))
      def update = render_ok(Controllers::PasswordResets::Update.call(params:))
    end
  end
end
