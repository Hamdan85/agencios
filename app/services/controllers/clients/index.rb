# frozen_string_literal: true

module Controllers
  module Clients
    class Index < Base
      def initialize(params:)
        @params = params
      end

      def call
        clients = workspace.clients.order(created_at: :desc)
        clients = clients.where(status: @params[:status]) if @params[:status].present?
        if @params[:q].present?
          like = "%#{escape_like(@params[:q])}%"
          clients = clients.where("clients.name ILIKE :q OR clients.company ILIKE :q", q: like)
        end
        collection_payload(clients, ClientSerializer, :clients, @params)
      end
    end
  end
end
