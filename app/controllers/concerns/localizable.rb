# frozen_string_literal: true

# Per-request locale switching. The default resolution serves the authenticated
# SPA/API: the user's own locale, then the tenant's. Public/token controllers
# (client portal, marketing pages) override #current_locale with their own
# resolution (client locale, ?locale param, Accept-Language).
module Localizable
  extend ActiveSupport::Concern

  included do
    around_action :switch_locale
  end

  private

  def current_locale
    normalize_locale(Current.user&.locale || Current.workspace&.locale)
  end

  def switch_locale(&)
    I18n.with_locale(current_locale, &)
  end

  # rescue_from handlers run outside the around_action (Rescue wraps Callbacks
  # in process_action) — re-wrap so error copy renders in the requester's locale.
  def rescue_with_handler(exception)
    I18n.with_locale(current_locale) { super }
  end

  def normalize_locale(candidate)
    return I18n.default_locale if candidate.blank?

    I18n.available_locales.find { |locale| locale.to_s == candidate.to_s } || I18n.default_locale
  end
end
