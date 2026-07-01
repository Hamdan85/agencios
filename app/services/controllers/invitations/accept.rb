# frozen_string_literal: true

module Controllers
  module Invitations
    # Verifies an invite token and creates the membership for the current user,
    # pointing the session at the joined workspace.
    class Accept < Base
      def initialize(params:)
        @params = params
      end

      def call
        data = Token.verify(@params[:token])
        raise Operations::Errors::Invalid, 'Convite inválido ou expirado.' unless data

        target = Workspace.find(data['workspace_id'])
        membership = target.memberships.find_or_create_by!(user: user) do |m|
          m.role = data['role']
        end

        Current.session.update!(workspace_id: target.id)
        { workspace: serialize(target, WorkspaceSerializer), role: membership.role }
      end
    end
  end
end
