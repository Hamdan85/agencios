# frozen_string_literal: true

module Api
  module V1
    # Lightweight, table-free invitations: an invite is a signed token carrying
    # the workspace id, email and role. Accepting it creates the membership.
    class InvitationsController < BaseController
      allow_unauthenticated_access only: %i[accept]

      def index   = render_ok(Controllers::Invitations::Index.call)
      def create  = render_created(Controllers::Invitations::Create.call(params:))
      def accept  = render_ok(Controllers::Invitations::Accept.call(params:))
      def destroy = render_ok(Controllers::Invitations::Destroy.call)
    end
  end
end
