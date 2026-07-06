# frozen_string_literal: true

module Controllers
  module Public
    module Approvals
      class ApproveCreative < Controllers::Base
        def initialize(ticket:, params:)
          @ticket = ticket
          @params = params
        end

        def call
          creative = @ticket.creatives.find(@params[:creative_id])
          Operations::Approvals::DecideCreative.call(
            creative: creative, decision: 'approved', actor: @ticket.project.client
          )
          { ok: true, approved: @ticket.reload.fully_approved? }
        end
      end
    end
  end
end
