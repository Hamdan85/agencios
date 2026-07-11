# frozen_string_literal: true

# Public status page for a Meta data-deletion request. The data-deletion callback
# returns a URL pointing here with a `code`; the user visits to confirm. Deletion
# is synchronous, so this always reports complete.
class DataDeletionController < ActionController::Base
  include Localizable

  def show
    @code = params[:code].to_s
    render layout: false
  end

  private

  # Public status page: resolve the visitor's locale (explicit ?locale →
  # persisted cookie → Accept-Language → default).
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
