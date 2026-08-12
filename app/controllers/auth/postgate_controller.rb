# frozen_string_literal: true

module Auth
  # The landing page PostGate's hosted-connect flow redirects the browser back
  # to once a network authorizes (or fails) — see
  # Operations::Social::Postgate::CreateConnectUrl for how `return_url` is built
  # and Controllers::Auth::Postgate::ReturnFromConnect for the persistence.
  #
  # Mirrors Auth::OmniauthController#callback: same signed-state round trip, same
  # `/auth/social-connected` success/failure landing page, so the existing popup
  # closer keeps working unchanged for both the direct and PostGate flows.
  class PostgateController < ActionController::Base
    skip_forgery_protection

    def return_from_connect
      result = Controllers::Auth::Postgate::ReturnFromConnect.call(state: params[:state], params: params)
      redirect_to_status(client_id: result[:client_id], connected: result[:network], link: result[:link])
    rescue Operations::Errors::Invalid
      redirect_to_status(error: 'state')
    rescue StandardError => e
      Rails.logger.warn("[Auth::Postgate] #{params[:connection_platform]}: #{e.message}")
      redirect_to_status(error: params[:connection_platform].presence || 'postgate')
    end

    private

    def redirect_to_status(client_id: nil, connected: nil, error: nil, link: nil)
      query = { client_id: client_id, connected: connected, error: error, link: link.presence }.compact
      redirect_to("/auth/social-connected?#{query.to_query}", allow_other_host: false)
    end
  end
end
