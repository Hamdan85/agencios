# frozen_string_literal: true

module Vendors
  module OpenRouter
    # Raised when OpenRouter returns an unexpected/empty result the generic
    # HTTP-status mapping in Vendors::Base can't express (e.g. a 200 with no image).
    class Error < Vendors::Base::Error; end
  end
end
