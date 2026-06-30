class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # --- ActiveAdmin auth (staff-only) ----------------------------------------
  # ActiveAdmin controllers inherit from ApplicationController. The internal
  # admin reuses the app's session cookie and is gated on User#staff? — there is
  # no separate admin user model.
  helper_method :current_staff_user

  def current_staff_user
    return @current_staff_user if defined?(@current_staff_user)

    token   = cookies.signed[:session_id]
    session = token.present? ? Session.find_by(token: token) : nil
    user    = session&.user
    @current_staff_user = user&.staff? ? user : nil
  end

  def authenticate_staff!
    return if current_staff_user

    redirect_to "/", alert: "Acesso restrito à equipe da plataforma."
  end
end
