# frozen_string_literal: true

module Controllers
  module Account
    # Updates the signed-in user's own profile (display name + UI locale).
    # E-mail and password have their own dedicated, credential-checked flows.
    class Update < Base
      def initialize(params:)
        @params = params
      end

      def call
        user.update!(profile_params)
        Controllers::Me::Show.call
      end

      private

      def profile_params
        @params.fetch(:user, {}).permit(:name, :locale)
      end
    end
  end
end
