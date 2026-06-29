# frozen_string_literal: true

module Api
  module V1
    class MeetingsController < BaseController
      def index   = render_ok(Controllers::Meetings::Index.call(params:))
      def show    = render_ok(Controllers::Meetings::Show.call(params:))
      def create  = render_created(Controllers::Meetings::Create.call(params:))
      def update  = render_ok(Controllers::Meetings::Update.call(params:))
      def destroy = render_ok(Controllers::Meetings::Destroy.call(params:))
    end
  end
end
