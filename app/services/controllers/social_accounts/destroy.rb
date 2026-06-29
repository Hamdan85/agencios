# frozen_string_literal: true

module Controllers
  module SocialAccounts
    class Destroy < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        client = workspace.clients.find(@params[:client_id])
        client.social_accounts.find(@params[:id]).destroy!
        { message: "Conta desconectada." }
      end
    end
  end
end
