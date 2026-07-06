# frozen_string_literal: true

module Controllers
  module Public
    module Approvals
      class RequestChanges < Controllers::Base
        def initialize(ticket:, params:)
          @ticket = ticket
          @params = params
        end

        def call
          creative = @ticket.creatives.find(@params[:creative_id])
          Operations::Approvals::DecideCreative.call(
            creative: creative, decision: 'changes_requested',
            actor: @ticket.project.client, feedback: @params[:feedback]
          )
          { ok: true }
        end
      end
    end
  end
end
