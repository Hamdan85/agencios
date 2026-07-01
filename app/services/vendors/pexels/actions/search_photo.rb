# frozen_string_literal: true

module Vendors
  module Pexels
    module Actions
      # Returns the single best stock photo for a query (or nil), with the
      # orientation mapped from a creative aspect ratio.
      class SearchPhoto
        def self.call(...) = new(...).call

        def initialize(query:, aspect_ratio: nil)
          @query       = query
          @orientation = orientation_for(aspect_ratio)
        end

        def call
          Vendors::Pexels::Client.new.search(
            query: @query, per_page: 10, orientation: @orientation
          ).first
        end

        private

        # Pexels accepts landscape | portrait | square.
        def orientation_for(aspect)
          return nil if aspect.blank?

          w, h = aspect.to_s.split(%r{[:x/]}).map(&:to_i)
          return nil if w.to_i.zero? || h.to_i.zero?

          if w == h then 'square'
          elsif h > w then 'portrait'
          else 'landscape'
          end
        end
      end
    end
  end
end
