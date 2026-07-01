# frozen_string_literal: true

# One per workspace — integration credentials + workspace-level preferences.
# Brand identity (name, voice, colors, handle, logo, avatar) lives on Workspace.
class Setting < ApplicationRecord
  belongs_to :workspace

  encrypts :google_access_token, :google_refresh_token, :mercadopago_access_token

  def google_connected? = google_access_token.present?
  def mercadopago_connected? = mercadopago_access_token.present?

  # Whether a real payment link can actually be generated: either this
  # workspace connected its own MP account, or the platform's app-level
  # token (Vendors::MercadoPago::Client) covers it — the single-tenant
  # default. Broader than `mercadopago_connected?`, which is scoped to the
  # marketplace OAuth connection shown on the Settings page.
  def payment_links_available? = mercadopago_connected? || Vendors::MercadoPago::Client.platform_configured?
end
