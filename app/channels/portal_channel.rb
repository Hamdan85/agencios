# frozen_string_literal: true

# Login-less client-central live updates: metric_updated (real-time campaign
# metrics). Authorized purely by the client's approval_token passed as `token` —
# there is no current_user (the portal is login-less). Streams the client's own
# `portal_<client_id>` channel only.
class PortalChannel < ApplicationCable::Channel
  def subscribed
    client = Client.find_by(approval_token: params[:token].to_s.presence)
    return reject if client.nil?

    stream_from "portal_#{client.id}"
  end

  def unsubscribed
    stop_all_streams
  end
end
