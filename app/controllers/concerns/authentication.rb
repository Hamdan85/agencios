# frozen_string_literal: true

# Session-cookie auth + per-request tenant resolution into `Current`.
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private

  def authenticated?
    resume_session
  end

  def require_authentication
    resume_session || request_authentication
  end

  def require_manager
    return if performed?
    return if Current.membership&.can_manage?

    render json: { error: "Acesso restrito a gestores do workspace.", code: "manager_required" },
           status: :forbidden
  end

  def resume_session
    Current.session ||= find_session_by_cookie
    resolve_current_workspace if Current.session
    Current.session
  end

  # Resolve the active tenant from the session's stored workspace_id, validating
  # the user is still a member; fall back to the user's first membership.
  def resolve_current_workspace
    return if Current.workspace

    session = Current.session
    workspace = nil

    if session.workspace_id
      candidate = Workspace.find_by(id: session.workspace_id)
      workspace = candidate if candidate&.memberships&.exists?(user_id: session.user_id)
    end

    workspace ||= Membership.where(user_id: session.user_id).order(:created_at).first&.workspace
    return unless workspace

    session.update_column(:workspace_id, workspace.id) if session.workspace_id != workspace.id
    Current.workspace  = workspace
    Current.membership = workspace.memberships.find_by(user_id: session.user_id)
  end

  def find_session_by_cookie
    token = cookies.signed[:session_id]
    return if token.blank?

    session = Session.find_by(token: token)
    return unless session

    if session.expired?
      session.destroy
      return
    end

    session.touch_activity!
    session
  end

  def request_authentication
    render json: { error: "Unauthorized" }, status: :unauthorized
  end

  def start_new_session_for(user)
    user.sessions.create!(
      token:          Session.generate_token,
      last_active_at: Time.current,
      expires_at:     Session::IDLE_TTL.from_now,
      user_agent:     request.user_agent,
      ip_address:     request.remote_ip
    ).tap do |session|
      Current.session = session
      cookies.signed.permanent[:session_id] = session_cookie_options(session.token)
    end
  end

  def session_cookie_options(token)
    {
      value:     token,
      httponly:  true,
      same_site: :lax,
      secure:    !Rails.env.local?
    }
  end

  def terminate_session
    Current.session&.destroy
    cookies.delete(:session_id)
  end
end
