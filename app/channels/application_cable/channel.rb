# frozen_string_literal: true

module ApplicationCable
  class Channel < ActionCable::Channel::Base
    private

    def member_of?(workspace_id)
      return false if workspace_id.blank?

      Membership.exists?(workspace_id: workspace_id, user_id: current_user.id)
    end
  end
end
