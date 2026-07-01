# frozen_string_literal: true

# The content-strategy planning session: the chat transcript plus the latest
# proposed plan (rendered as a preview in the UI before it's applied).
class StrategySessionSerializer < ActiveModel::Serializer
  attributes :id, :project_id, :status, :messages, :proposed_plan, :created_at

  def messages = Array(object.messages)
  def proposed_plan = object.proposed_plan.presence || {}
  def created_at = object.created_at.iso8601
end
