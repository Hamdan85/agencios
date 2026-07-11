# frozen_string_literal: true

module Controllers
  module Account
    # Attaches (or replaces) the signed-in user's avatar from a multipart upload.
    class UpdateAvatar < Base
      def initialize(params:)
        @params = params
      end

      def call
        file = @params[:avatar]
        raise Operations::Errors::Invalid, I18n.t('api.account.no_image_uploaded') if file.blank?

        user.avatar.attach(file)
        Controllers::Me::Show.call
      end
    end
  end
end
