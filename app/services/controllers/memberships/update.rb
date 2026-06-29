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
        membership_record.update!(role: @params.require(:role))
        { membership: serialize(membership_record, MembershipSerializer) }
      end
    end
  end
end
