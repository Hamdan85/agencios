# frozen_string_literal: true

# One per workspace — integration credentials + workspace-level preferences.
# Brand identity (name, voice, colors, handle, logo, avatar) lives on Workspace.
class Setting < ApplicationRecord
  belongs_to :workspace

  encrypts :google_access_token, :google_refresh_token, :mercadopago_access_token

  def google_connected? = google_access_token.present?
  def mercadopago_connected? = mercadopago_access_token.present?
end
