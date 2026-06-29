# frozen_string_literal: true

# Connecting/reconnecting an account is a member action; removing it is
# manager-gated (inherited default).
class SocialAccountPolicy < ApplicationPolicy
  def reconnect? = member?
end
