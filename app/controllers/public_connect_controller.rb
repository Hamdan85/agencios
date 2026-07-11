# frozen_string_literal: true

# Public, login-less per-client connect page. The agency shares the tokenized
# URL (`/conectar/:token`) with their client; the client opens it and connects
# their own Instagram/Facebook — no agencios account, no Business Manager. The
# token is the bearer credential (verified in the service), so CSRF doesn't apply.
class PublicConnectController < ActionController::Base
  include Localizable

  skip_forgery_protection

  def show
    @data = Controllers::PublicConnect::Show.call(token: params[:token])
    render layout: false
  rescue Operations::Errors::Invalid
    render :invalid, layout: false, status: :not_found
  end

  # GET /conectar/:token/authorize?network=instagram — 302 to the provider's
  # OAuth dialog (opened in the popup by the page).
  def authorize
    result = Controllers::PublicConnect::Authorize.call(
      token: params[:token], network: params[:network]
    )
    redirect_to result[:url], allow_other_host: true
  rescue Operations::Errors::Invalid
    redirect_to("/conectar/#{params[:token]}?error=network", allow_other_host: false)
  rescue Vendors::Base::Error => e
    Rails.logger.warn("[PublicConnect] authorize #{params[:network]}: #{e.message}")
    redirect_to("/conectar/#{params[:token]}?error=oauth", allow_other_host: false)
  end

  private

  # Client-facing page: resolve the visitor's locale (explicit ?locale →
  # persisted cookie → Accept-Language → default). No signed-in user here.
  def current_locale
    normalize_locale(params[:locale] || cookies[:locale] || header_locale)
  end

  def header_locale
    accept = request.headers['Accept-Language'].to_s
    return 'pt-BR' if accept =~ /\bpt\b|pt-/i
    return 'en' if accept =~ /\ben\b|en-/i

    nil
  end
end
