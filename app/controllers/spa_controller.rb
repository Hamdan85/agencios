# frozen_string_literal: true

# Serves the layout-less HTML shell that boots the React SPA. Every HTML GET
# that isn't an API/asset route falls through here (see the routes catch-all).
class SpaController < ActionController::Base
  protect_from_forgery with: :exception
  include Localizable

  def index
    render template: 'spa/index', layout: false
  end

  private

  # Anonymous-friendly resolution: the signed-in user's locale when the session
  # cookie resolves, else ?locale → cookie → Accept-Language → default. The
  # resolved locale reaches the SPA via <html lang> (read by i18n.js before /me).
  def current_locale
    normalize_locale(session_user_locale || params[:locale] || cookies[:locale] || header_locale)
  end

  def session_user_locale
    token = cookies.signed[:session_id]
    return if token.blank?

    Session.find_by(token: token)&.user&.locale
  end

  def header_locale
    accept = request.headers['Accept-Language'].to_s
    return 'pt-BR' if accept =~ /\bpt\b|pt-/i
    return 'en' if accept =~ /\ben\b|en-/i

    nil
  end
end
