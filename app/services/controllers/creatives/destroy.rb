# frozen_string_literal: true

module Controllers
  module Creatives
    class Destroy < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        ticket = workspace.tickets.find(@params[:ticket_id])
        ticket.creatives.find(@params[:id]).destroy!
        { message: I18n.t('api.creatives.removed') }
      end
    end
  end
end
