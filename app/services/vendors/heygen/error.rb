# frozen_string_literal: true

module Vendors
  module Heygen
    # HeyGen-specific API error. Carries the vendor error `code` and `param`
    # (v3 structured errors) in addition to the base status/body.
    class Error < Vendors::Base::Error
      attr_reader :code, :param

      def initialize(message = nil, status: nil, body: nil, code: nil, param: nil)
        @code = code
        @param = param
        super(message, status: status, body: body)
      end

      # Builds an Error from either a v3 structured error hash
      # ({ "code", "message", "param" }) or a legacy v2 string.
      def self.from_body(error, status: nil, body: nil)
        if error.is_a?(Hash)
          new(
            error["message"] || error["code"] || "HeyGen error",
            status: status, body: body,
            code: error["code"], param: error["param"]
          )
        else
          new(error.to_s, status: status, body: body)
        end
      end
    end
  end
end
