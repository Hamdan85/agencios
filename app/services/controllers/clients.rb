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

    # Client scalar attributes (contact + brand identity text). Brand assets
    # (logo, avatar) upload separately via the brand_assets action.
    ATTRS_PERMIT = %i[
      name company email phone document notes status
      brand_voice default_handle brand_primary_color brand_secondary_color
    ].freeze
  end
end
