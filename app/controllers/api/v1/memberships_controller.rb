# frozen_string_literal: true

module Api
  module V1
    class MembershipsController < BaseController
      def index   = render_ok(Controllers::Memberships::Index.call(params:))
      def update  = render_ok(Controllers::Memberships::Update.call(params:))
      def destroy = render_ok(Controllers::Memberships::Destroy.call(params:))
    end
  end
end
