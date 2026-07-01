# frozen_string_literal: true

module Operations
  module Autopilot
    # Whether a ticket can run on autopilot ("GO mode"). Eligible iff EVERY scoped
    # creative type is auto-generatable (per the Creatives registry) — autopilot
    # only produces creatives it can make itself (carousel/image/video). A type
    # that must be uploaded (e.g. `cover`) blocks the run.
    #
    # Returns { eligible:, blocking_types: [...] }.
    class Eligibility < Operations::Base
      def initialize(ticket:)
        @ticket = ticket
      end

      def call
        types = @ticket.creative_types_list
        return { eligible: false, blocking_types: [] } if types.blank?

        blocking = types.reject { |type| generatable?(type) }
        { eligible: blocking.empty?, blocking_types: blocking.uniq }
      end

      private

      def generatable?(type)
        spec = ::Creatives.spec_for(type)
        spec.present? && spec[:generatable] == true
      end
    end
  end
end
