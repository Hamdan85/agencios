# frozen_string_literal: true

class GenerationSerializer < ActiveModel::Serializer
  attributes :id, :kind, :status, :provider, :external_id, :cost_cents,
             :metered, :creative_id, :params, :result, :failure_reason, :created_at

  def kind = object.kind
  def status = object.status
  def metered = object.metered?
  def created_at = object.created_at&.iso8601
end
