# frozen_string_literal: true

class WorkspaceSerializer < ActiveModel::Serializer
  attributes :id, :name, :slug, :timezone, :locale, :brand_voice, :default_handle,
             :brand_primary_color, :brand_secondary_color, :plan, :seat_count,
             :seat_limit, :trialing, :billing_active, :logo_url, :role,
             :godfathered, :credits_available, :over_seat_limit

  def plan = object.plan
  def trialing = object.trialing?
  def billing_active = object.billing_active?
  def godfathered = object.godfathered?
  def over_seat_limit = object.over_seat_limit?
  # nil for godfathered workspaces (credits are unlimited/not tracked).
  def credits_available = object.godfathered? ? nil : object.credits_available

  def seat_limit
    limit = object.seat_limit
    limit.infinite? ? nil : limit
  end

  def role = Current.membership&.role

  def logo_url
    return nil unless object.logo.attached?

    Rails.application.routes.url_helpers.rails_blob_url(object.logo, host: SystemConfig.app_host)
  rescue StandardError
    nil
  end
end
