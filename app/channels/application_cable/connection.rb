# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      # Anonymous connections are allowed (current_user stays nil) so the
      # login-less client portal can subscribe to PortalChannel by token. Every
      # authenticated channel rejects a nil current_user, so this does not widen
      # access to the member-only streams (board/ticket/generations/strategy).
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      token = cookies.signed[:session_id]
      session = Session.find_by(token: token) if token.present?
      session&.user
    end
  end
end
