# frozen_string_literal: true

module Api
  module V1
    class PushSubscriptionsController < BaseController
      def create  = render_created(Controllers::PushSubscriptions::Create.call(params:))
      def destroy = render_ok(Controllers::PushSubscriptions::Destroy.call(params:))
    end
  end
end
