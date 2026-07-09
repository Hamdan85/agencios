# frozen_string_literal: true

# Per-session content-strategy updates: plan_generating, proposal_ready,
# plan_failed. The plan is generated OFF the request (Sidekiq) and pushed here
# when ready, so the client never has to hold a multi-minute streaming request
# open (those were being severed by the CDN). Only members of the session's
# workspace may subscribe.
class StrategyChannel < ApplicationCable::Channel
  def subscribed
    return reject if current_user.nil?

    session = StrategySession
              .where(workspace_id: current_user.workspaces.select(:id))
              .find_by(id: params[:session_id])
    return reject unless session

    stream_from "strategy_session_#{session.id}"
  end

  def unsubscribed
    stop_all_streams
  end
end
