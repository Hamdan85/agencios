# frozen_string_literal: true

module Operations
  module Users
    # Creates a user and bootstraps their first workspace (they become owner).
    class Register < Operations::Base
      def initialize(email:, password:, name:, workspace_name: nil)
        @email = email
        @password = password
        @name = name
        @workspace_name = workspace_name
      end

      def call
        user = User.create!(email: @email, password: @password, name: @name)
        workspace = Operations::Workspaces::SetupForUser.call(user: user, name: @workspace_name)
        [user, workspace]
      end
    end
  end
end
