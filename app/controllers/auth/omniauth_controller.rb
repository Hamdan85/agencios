# frozen_string_literal: true

module Auth
  # Handles social-network OAuth callbacks: the service verifies the signed state
  # (which carries the connecting client), exchanges the code via the network
  # vendor, and persists the SocialAccount(s) onto that client. The controller maps
  # the result to a browser redirect back to the client's page.
  class OmniauthController < ActionController::Base
    def callback
      result = Controllers::Auth::Omniauth::Callback.call(
        provider: params[:provider], code: params[:code], state: params[:state]
      )
      redirect_to(
        "/auth/social-connected?client_id=#{result[:client_id]}&connected=#{result[:slug]}",
        allow_other_host: false
      )
    rescue Operations::Errors::Invalid
      redirect_to("/auth/social-connected?error=state", allow_other_host: false)
    rescue StandardError => e
      Rails.logger.warn("[Auth::Omniauth] #{params[:provider]}: #{e.message}")
      redirect_to("/auth/social-connected?error=#{params[:provider]}", allow_other_host: false)
    end

    def failure
      redirect_to("/auth/social-connected?error=oauth", allow_other_host: false)
    end

    # Tiny inline page — posts a postMessage to the opener and closes the popup.
    # Falls back to a full redirect when not opened as a popup.
    def social_connected
      @client_id = params[:client_id].to_s
      @connected = params[:connected].to_s
      @error     = params[:error].to_s
      render layout: false
    end
  end
end
