# frozen_string_literal: true

module Api
  module V1
    # One chat turn of the strategy planner, streamed to the client over SSE.
    # Text deltas arrive as `delta` events; the final structured plan (when the
    # agent proposes one) as a `proposal` event; then `done`. Business logic lives
    # in Operations::Strategy::Converse — this only relays its output to the stream.
    class StrategyMessagesController < BaseController
      include ActionController::Live

      # POST /api/v1/strategy_sessions/:strategy_session_id/messages
      def create
        session = Current.workspace.strategy_sessions.find(params[:strategy_session_id])
        authorize(session.project, :update?)

        response.headers["Content-Type"]      = "text/event-stream"
        response.headers["Cache-Control"]     = "no-cache"
        response.headers["X-Accel-Buffering"] = "no" # let nginx pass chunks through unbuffered

        result = Operations::Strategy::Converse.call(
          session: session,
          content: params[:content],
          on_generating: -> { write_sse("generating", {}) },
        ) do |chunk|
          write_sse("delta", text: chunk)
        end

        write_sse("proposal", plan: result.proposal) if result.proposal
        write_sse("done", status: session.reload.status)
      rescue Pundit::NotAuthorizedError
        write_sse("error", message: "Você não tem permissão para planejar este projeto.")
      rescue Operations::Errors::Invalid => e
        write_sse("error", message: e.message)
      rescue ActiveRecord::RecordNotFound
        write_sse("error", message: "Sessão não encontrada.")
      rescue StandardError => e
        Rails.logger.error("[StrategyMessages] #{e.class}: #{e.message}")
        write_sse("error", message: "Erro ao processar a mensagem.")
      ensure
        response.stream.close
      end

      private

      def write_sse(event, data)
        response.stream.write("event: #{event}\ndata: #{data.to_json}\n\n")
      end
    end
  end
end
