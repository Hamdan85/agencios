# frozen_string_literal: true

# Workspace-wide creative-generation updates: generation_progress, generation_done.
# The connection identifies by current_user; only members of the workspace may
# subscribe.
class GenerationsChannel < ApplicationCable::Channel
  def subscribed
    return reject unless member_of?(params[:workspace_id])

    stream_from "generations_#{params[:workspace_id]}"
  end

  def unsubscribed
    stop_all_streams
  end
end
