# frozen_string_literal: true

class PostSerializer < ActiveModel::Serializer
  include PostPayload

  attributes :id, :status, :scheduled_at, :published_at, :unpublished_at, :caption, :permalink,
             :external_post_id, :provider, :username, :metrics, :ticket_id, :social_account_id,
             :failure_reason
end
