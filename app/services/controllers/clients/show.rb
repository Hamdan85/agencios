# frozen_string_literal: true

module Controllers
  module Clients
    class Show < Base
      def initialize(params:)
        @params = params
      end

      def call
        client = workspace.clients.find(@params[:id])
        authorize!(client, :show?)
        {
          client: serialize(client, ClientSerializer),
          projects: serialize_collection(client.projects.order(created_at: :desc), ProjectSerializer),
          invoices: serialize_collection(client.invoices.order(created_at: :desc), InvoiceSerializer),
          social_accounts: serialize_collection(client.social_accounts.order(:provider), SocialAccountSerializer)
        }
      end
    end
  end
end
