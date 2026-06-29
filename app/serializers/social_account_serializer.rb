# frozen_string_literal: true

# Never emits any token columns (user_access_token / page_access_token /
# refresh_token are encrypted and stay server-side).
class SocialAccountSerializer < ActiveModel::Serializer
  attributes :id, :provider, :username, :status, :token_expired,
             :last_synced_at, :scopes, :created_at

  def provider = object.provider
  def status = object.status
  def token_expired = object.token_expired?
  def last_synced_at = object.last_synced_at&.iso8601
  def created_at = object.created_at&.iso8601
end
