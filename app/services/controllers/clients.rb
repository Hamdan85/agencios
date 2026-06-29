# frozen_string_literal: true

module Controllers
  # Explicit namespace for the client HTTP-layer services. Holds the strong-params
  # shape for the positioning bag, shared by Create / Update / positioning actions.
  module Clients
    # Every positioning key is a scalar except content_pillars, which is an array.
    POSITIONING_PERMIT = [
      *(Client::POSITIONING_KEYS - Client::ARRAY_POSITIONING_KEYS).map(&:to_sym),
      { content_pillars: [] }
    ].freeze
  end
end
