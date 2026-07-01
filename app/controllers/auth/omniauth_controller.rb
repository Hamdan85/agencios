# frozen_string_literal: true

module Auth
  # Handles social-network OAuth callbacks: the service verifies the signed state
  # (which carries the connecting client + requested network), exchanges the code
  # via the network vendor, and persists the SocialAccount(s) onto that client.
  # When a Meta login exposes several Pages, the callback renders a Page picker
  # (in the popup) that posts back to #choose_page.
  #
  # These are OAuth round-trip endpoints (the IdP redirects the browser here and
  # the picker posts a server-issued nonce), so CSRF tokens don't apply.
  class OmniauthController < ActionController::Base
    skip_forgery_protection

    def callback
      result = Controllers::Auth::Omniauth::Callback.call(
        provider: params[:provider], code: params[:code], state: params[:state]
      )
      render_result(result)
    rescue Controllers::Auth::Omniauth::MetaConnect::InstagramRequired
      redirect_to_status(error: 'no_instagram')
    rescue Operations::Errors::Invalid
      redirect_to_status(error: 'state')
    rescue StandardError => e
      Rails.logger.warn("[Auth::Omniauth] #{params[:provider]}: #{e.message}")
      redirect_to_status(error: params[:provider])
    end

    # POST /auth/facebook/select — the user picked which Page to attach to the client.
    def choose_page
      result = Controllers::Auth::Omniauth::SelectPage.call(
        nonce: params[:nonce], page_id: params[:page_id]
      )
      render_result(result)
    rescue Controllers::Auth::Omniauth::MetaConnect::InstagramRequired
      redirect_to_status(error: 'no_instagram')
    rescue Operations::Errors::Invalid
      redirect_to_status(error: 'expired')
    rescue StandardError => e
      Rails.logger.warn("[Auth::Omniauth] choose_page: #{e.message}")
      redirect_to_status(error: 'meta')
    end

    def failure
      redirect_to_status(error: 'oauth')
    end

    # Tiny inline page — signals the opener and closes the popup. Falls back to a
    # full redirect when not opened as a popup.
    def social_connected
      @client_id = params[:client_id].to_s
      @connected = params[:connected].to_s
      @error     = params[:error].to_s
      @link      = params[:link].to_s
      render layout: false
    end

    private

    # Either render the Page picker (multi-Page Meta login) or redirect to the
    # success page that closes the popup.
    def render_result(result)
      if result[:result] == :select
        @nonce     = result[:nonce]
        @client_id = result[:client_id]
        @network   = result[:network]
        @pages     = result[:pages]
        render :select_page, layout: false
      else
        redirect_to_status(client_id: result[:client_id], connected: result[:network], link: result[:link])
      end
    end

    def redirect_to_status(client_id: nil, connected: nil, error: nil, link: nil)
      query = { client_id: client_id, connected: connected, error: error, link: link.presence }.compact
      redirect_to("/auth/social-connected?#{query.to_query}", allow_other_host: false)
    end
  end
end
