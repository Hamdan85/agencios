# frozen_string_literal: true

# Workspace-wide prepaid credit-balance updates: balance_changed. The connection
# identifies by current_user; only members of the workspace may subscribe.
class CreditsChannel < ApplicationCable::Channel
  def subscribed
    return reject unless member_of?(params[:workspace_id])

    stream_from "credits_#{params[:workspace_id]}"
  end

  def unsubscribed
    stop_all_streams
  end
end
