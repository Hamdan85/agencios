# frozen_string_literal: true

module Controllers
  module Memberships
    class Index < Base
      def initialize(params: {})
        @params = params || {}
      end

      def call
        memberships = workspace.memberships.includes(:user).order(:created_at)
        if @params[:q].present?
          like = "%#{escape_like(@params[:q])}%"
          memberships = memberships.joins(:user).where('users.name ILIKE :q OR users.email ILIKE :q', q: like)
        end
        collection_payload(memberships, MembershipSerializer, :memberships, @params)
      end
    end
  end
end
