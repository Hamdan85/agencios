# frozen_string_literal: true

module Operations
  module Tickets
    # Carries the funnel's accumulated context FORWARD into the status the ticket
    # just entered, so the team rarely has to retype anything. Two layers:
    #
    #   1. Deterministic seed — copy fields that are literally the same concept
    #      from an earlier stage into the new stage's BLANK fields (never clobber
    #      what the team already wrote). Channels / creative_type / scheduled_at
    #      already mirror onto columns, so this only covers the prose carries.
    #   2. AI fill — Operations::Ai::FillFields(only_blank: true) completes the
    #      remaining empty fields of the new stage from ALL prior context.
    #
    # Runs in the background (CarryOverFieldsJob), enqueued by ChangeStatus on a
    # forward transition.
    class CarryOver < Operations::Base
      # target_key => [source_status, source_key]; applied only when the target
      # is still blank.
      # NOTE: production's `caption` is deliberately NOT seeded from scoping's
      # `copy_brief` — copy_brief is internal messaging direction, not
      # publish-ready copy. Leaving it blank lets Operations::Ai::FillFields
      # write a real caption from it instead of leaking the brief verbatim.
      SEEDS = {
        'scoping' => { 'copy_brief' => %w[ideation brief] }
      }.freeze

      def initialize(ticket:, status: nil)
        @ticket = ticket
        @status = (status || ticket.status).to_s
      end

      def call
        seed_deterministic
        Operations::Ai::FillFields.call(ticket: @ticket, only_blank: true)
      rescue StandardError => e
        Rails.logger.warn("[CarryOver] failed for ticket #{@ticket.id} (#{@status}): #{e.message}")
        { filled: [] }
      end

      private

      def seed_deterministic
        map = SEEDS[@status]
        return if map.blank?

        current = @ticket.fields_for(@status)
        values = map.each_with_object({}) do |(target, (src_status, src_key)), acc|
          next if current[target].present?

          val = @ticket.fields_for(src_status)[src_key]
          acc[target] = val if val.present?
        end
        return if values.empty?

        Operations::Tickets::UpdateFields.call(ticket: @ticket, status: @status, values: values)
      end
    end
  end
end
