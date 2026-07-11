# frozen_string_literal: true

module Controllers
  module Memberships
    class Update < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        membership_record = workspace.memberships.find(@params[:id])
        new_role = @params.require(:role).to_s

        # The owner role carries billing + workspace deletion — only an owner
        # grants it or takes it away, and the workspace can never end up with
        # no owner at all.
        if (new_role == 'owner' || membership_record.owner?) && !Current.membership&.owner?
          raise Operations::Errors::Forbidden, I18n.t('api.memberships.owner_role_restricted')
        end
        if membership_record.owner? && new_role != 'owner' &&
           workspace.memberships.where(role: :owner).where.not(id: membership_record.id).none?
          raise Operations::Errors::Invalid,
                I18n.t('api.memberships.last_owner')
        end

        membership_record.update!(role: new_role)
        { membership: serialize(membership_record, MembershipSerializer) }
      end
    end
  end
end
