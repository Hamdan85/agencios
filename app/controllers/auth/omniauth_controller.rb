# frozen_string_literal: true

module Auth
  # Handles social-network OAuth callbacks: the service verifies the signed state
  # (which carries the connecting workspace), exchanges the code via the network
  # vendor, and persists the SocialAccount(s). The controller maps the result to
  # a browser redirect.
  class OmniauthController < ActionController::Base
    def callback
      slug = Controllers::Auth::Omniauth::Callback.call(
        provider: params[:provider], code: params[:code], state: params[:state]
      )
      redirect_to("/configuracoes?connected=#{slug}", allow_other_host: false)
    rescue Operations::Errors::Invalid
      redirect_to("/configuracoes?error=state", allow_other_host: false)
    rescue StandardError => e
      Rails.logger.warn("[Auth::Omniauth] #{params[:provider]}: #{e.message}")
      redirect_to("/configuracoes?error=#{params[:provider]}", allow_other_host: false)
    end

    def failure
      redirect_to("/configuracoes?error=oauth", allow_other_host: false)
    end
  end
end
