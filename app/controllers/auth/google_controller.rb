# frozen_string_literal: true

module Auth
  # "Sign in / Sign up with Google" — a full-page OAuth redirect flow (the user
  # isn't authenticated yet, so no popup). `start` sends the browser to Google;
  # `callback` exchanges the code, finds-or-creates the user + workspace, opens a
  # cookie session, and redirects into the SPA. Distinct from OmniauthController,
  # which connects a client's social accounts for an already-authenticated user.
  class GoogleController < ActionController::Base
    include Authentication
    allow_unauthenticated_access only: %i[start callback]

    LOGIN_PATH = "/login"

    def start
      url = Controllers::Auth::Google::Start.call(return_to: params[:return_to])
      redirect_to(url, allow_other_host: true)
    end

    def callback
      # User declined consent (or Google returned an error) → back to login.
      return redirect_to("#{LOGIN_PATH}?error=google") if params[:error].present?

      result = Controllers::Auth::Google::Callback.call(code: params[:code], state: params[:state])
      start_new_session_for(result[:user])
      redirect_to(result[:return_to], allow_other_host: false)
    rescue Operations::Errors::Invalid, Vendors::Base::Error => e
      Rails.logger.warn("[Auth::Google] #{e.class}: #{e.message}")
      redirect_to("#{LOGIN_PATH}?error=google")
    rescue StandardError => e
      Rails.logger.error("[Auth::Google] #{e.class}: #{e.message}")
      redirect_to("#{LOGIN_PATH}?error=google")
    end
  end
end
