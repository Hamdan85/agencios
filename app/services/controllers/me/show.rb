# frozen_string_literal: true

module Controllers
  module Me
    # The current identity payload (user + active workspace + memberships).
    # Reused by Sessions::Create / Registrations::Create for the post-auth
    # response (which omit the membership key).
    class Show < Base
      def initialize(include_membership: true)
        @include_membership = include_membership
      end

      def call
        payload = {
          user: serialize(user, UserSerializer),
          workspace: workspace && serialize(workspace, WorkspaceSerializer),
          workspaces: serialize_collection(user.workspaces.order(:created_at), WorkspaceSerializer),
          # Whether the user may still create another workspace (per-user limit).
          can_create_workspace: user.can_create_workspace?,
          # Public key the browser uses as the Web Push applicationServerKey.
          vapid_public_key: Rails.application.credentials.dig(:vapid, :public_key)
        }
        payload[:membership] = { role: membership&.role } if @include_membership
        payload
      end
    end
  end
end
