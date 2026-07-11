# frozen_string_literal: true

module Controllers
  module Memberships
    class Destroy < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        membership_record = workspace.memberships.find(@params[:id])
        raise Operations::Errors::Forbidden, I18n.t('api.memberships.cannot_remove_owner') if membership_record.owner?

        membership_record.destroy!
        { message: I18n.t('api.memberships.removed') }
      end
    end
  end
end
