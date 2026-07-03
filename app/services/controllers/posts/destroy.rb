# frozen_string_literal: true

module Controllers
  module Posts
    class Destroy < Base
      def initialize(params:)
        @params = params
      end

      def call
        ticket = workspace.tickets.find(@params[:ticket_id])
        post = ticket.posts.find(@params[:id])

        # Destroying is CANCELING a not-yet-live publication. A post already on
        # the network keeps its history — unpublish it instead (which preserves
        # the record and its metrics).
        unless post.status_scheduled? || post.status_failed?
          raise Operations::Errors::Invalid,
                'Só é possível cancelar publicações agendadas ou com falha. Para tirar um post do ar, despublique-o.'
        end

        post.destroy!
        { message: 'Agendamento cancelado.' }
      end
    end
  end
end
