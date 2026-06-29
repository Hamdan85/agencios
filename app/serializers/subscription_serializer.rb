# frozen_string_literal: true

class SubscriptionSerializer < ActiveModel::Serializer
  attributes :id, :plan, :status, :seats, :trialing, :trial_ends_at,
             :current_period_end, :cancel_at, :access_granted, :seat_limit

  def trialing = object.trialing?
  def access_granted = object.access_granted?
  def trial_ends_at = object.trial_ends_at&.iso8601
  def current_period_end = object.current_period_end&.iso8601
  def cancel_at = object.cancel_at&.iso8601
end
