# frozen_string_literal: true

module Admin
  # Platform-staff impersonation for support. Starting impersonation swaps the
  # session cookie to a fresh session for the target user, stashing the staff
  # member's own session token in a separate signed cookie so it can be restored.
  # Stopping restores the staff session and tears down the impersonation session.
  #
  # Guarded by User#staff? on start. Every start/stop is audit-logged.
  class ImpersonationsController < ApplicationController
    before_action :authenticate_staff!, only: :create

    def create
      staff = current_staff_user
      target = User.find(params[:user_id])

      if target.staff?
        return redirect_to("/admin", alert: "Não é possível personificar outro membro da equipe.")
      end

      original_token = cookies.signed[:session_id]
      session = new_session_for(target)

      # Keep the staff's own session so we can come back to it.
      set_cookie(:impersonator_session_id, original_token) if original_token.present?
      set_cookie(:session_id, session.token)

      AdminAuditLog.record(
        staff_user: staff, action: "impersonate_start", target: target,
        metadata: { email: target.email }, ip_address: request.remote_ip
      )

      redirect_to "/", allow_other_host: false
    end

    def destroy
      impersonator_token = cookies.signed[:impersonator_session_id]
      return redirect_to("/") if impersonator_token.blank?

      # Tear down the impersonation session (the current cookie) and restore the
      # staff session.
      current_token = cookies.signed[:session_id]
      Session.find_by(token: current_token)&.destroy if current_token.present?

      restored = Session.find_by(token: impersonator_token)
      AdminAuditLog.record(
        staff_user: restored&.user, action: "impersonate_stop",
        ip_address: request.remote_ip
      )

      set_cookie(:session_id, impersonator_token)
      cookies.delete(:impersonator_session_id)

      redirect_to "/admin", notice: "Personificação encerrada."
    end

    private

    def new_session_for(user)
      user.sessions.create!(
        token:          Session.generate_token,
        last_active_at: Time.current,
        expires_at:     Session::IDLE_TTL.from_now,
        user_agent:     request.user_agent,
        ip_address:     request.remote_ip
      )
    end

    def set_cookie(name, value)
      cookies.signed.permanent[name] = {
        value: value, httponly: true, same_site: :lax, secure: !Rails.env.local?
      }
    end
  end
end
