# frozen_string_literal: true

module Api
  module V1
    # One chat turn of the strategy planner. Only the conversational reply streams
    # over SSE (`delta` events, then `done`) — it returns in seconds. The heavy
    # plan build runs off the request (Sidekiq) and is pushed to the client over
    # Action Cable when ready, so this connection never stays open long enough for
    # Cloudflare/QUIC to sever it mid-turn. Logic lives in
    # Operations::Strategy::Converse — this only relays its output to the stream.
    class StrategyMessagesController < BaseController
      include ActionController::Live

      # The streamed reply is short, but a slow first token can still stall the
      # stream; a comment ping keeps bytes flowing as a cheap safety net.
      HEARTBEAT_INTERVAL = 15 # seconds

      # POST /api/v1/strategy_sessions/:strategy_session_id/messages
      def create
        session = Current.workspace.strategy_sessions.find(params[:strategy_session_id])
        authorize(session.project, :update?)

        response.headers['Content-Type']      = 'text/event-stream'
        response.headers['Cache-Control']     = 'no-cache'
        response.headers['X-Accel-Buffering'] = 'no' # let nginx pass chunks through unbuffered

        start_heartbeat

        Operations::Strategy::Converse.call(
          session: session,
          content: params[:content]
        ) do |chunk|
          write_sse('delta', text: chunk)
        end

        write_sse('done', status: session.reload.status)
      rescue Pundit::NotAuthorizedError
        write_sse('error', message: 'Você não tem permissão para planejar esta campanha.')
      rescue Operations::Errors::Invalid => e
        write_sse('error', message: e.message)
      rescue ActiveRecord::RecordNotFound
        write_sse('error', message: 'Sessão não encontrada.')
      rescue StandardError => e
        Rails.logger.error("[StrategyMessages] #{e.class}: #{e.message}")
        write_sse('error', message: 'Erro ao processar a mensagem.')
      ensure
        stop_heartbeat
        response.stream.close
      end

      private

      # Background pinger that writes an SSE comment every HEARTBEAT_INTERVAL so the
      # connection never idles past Cloudflare's cutoff during synchronous AI calls.
      # Shares @stream_mutex with write_sse so a ping never splits a real frame.
      def start_heartbeat
        @stream_mutex = Mutex.new
        @heartbeat = Thread.new do
          loop do
            sleep HEARTBEAT_INTERVAL
            @stream_mutex.synchronize { response.stream.write(": ping\n\n") }
          end
        rescue IOError, ActionController::Live::ClientDisconnected
          # Client went away — let the request unwind normally.
        end
      end

      def stop_heartbeat
        @heartbeat&.kill
      end

      def write_sse(event, data)
        (@stream_mutex ||= Mutex.new).synchronize do
          response.stream.write("event: #{event}\ndata: #{data.to_json}\n\n")
        end
      end
    end
  end
end
