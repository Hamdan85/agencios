# frozen_string_literal: true

module Controllers
  module Clients
    class Create < Base
      def initialize(params:)
        @params = params
      end

      def call
        authorize!(Client, :create?)
        client = Operations::Clients::Create.call(client_params)
        { client: serialize(client, ClientSerializer) }
      end

      private

      def client_params
        @params.require(:client).permit(
          :name, :company, :email, :phone, :document, :notes, :status,
          positioning: POSITIONING_PERMIT
        )
      end
    end
  end
end
