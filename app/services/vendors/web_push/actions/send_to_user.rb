# frozen_string_literal: true

module Vendors
  module WebPush
    module Actions
      # Preferred call site for delivering a Web Push message to all of a user's
      # registered browser subscriptions.
      class SendToUser
        def self.call(...) = new(...).call

        def initialize(user:, title:, body:, path: "/")
          @user = user
          @title = title
          @body = body
          @path = path
        end

        def call
          Vendors::WebPush::Client.send_to_user(@user, title: @title, body: @body, path: @path)
        end
      end
    end
  end
end
