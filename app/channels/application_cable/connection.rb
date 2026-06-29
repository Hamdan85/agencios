# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      token = cookies.signed[:session_id]
      session = Session.find_by(token: token) if token.present?
      session&.user || reject_unauthorized_connection
    end
  end
end
