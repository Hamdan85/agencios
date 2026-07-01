# frozen_string_literal: true

module Operations
  module Users
    # Resolves a Google OpenID profile to a User, in priority order:
    #   1. existing user with this `google_uid`            → sign in
    #   2. existing user with this verified email          → link + sign in
    #   3. nobody yet                                      → sign up (user + workspace)
    #
    # Linking/creation requires a Google-verified email, so an unverified address
    # can never claim an existing account. Returns the User.
    class FindOrCreateFromGoogle < Operations::Base
      def initialize(uid:, email:, name: nil, email_verified: false)
        @uid = uid.to_s
        @email = email.to_s.strip.downcase
        @name = name.presence
        @email_verified = email_verified
      end

      def call
        raise Operations::Errors::Invalid, 'Conta Google sem identificador.' if @uid.blank?
        raise Operations::Errors::Invalid, 'E-mail do Google ausente.' if @email.blank?

        existing_by_uid || link_existing_by_email || create_new
      end

      private

      def existing_by_uid
        user = User.find_by(google_uid: @uid)
        return unless user

        backfill!(user)
        user
      end

      def link_existing_by_email
        return unless @email_verified

        user = User.find_by(email: @email)
        return unless user

        user.update!(google_uid: @uid)
        backfill!(user)
        user
      end

      def create_new
        raise Operations::Errors::Invalid, 'E-mail do Google não verificado.' unless @email_verified

        user = User.create!(
          email: @email,
          name: @name,
          google_uid: @uid,
          confirmed_at: Time.current # Google already verified the address
        )
        Operations::Workspaces::SetupForUser.call(user: user)
        user
      end

      # Fill in fields a password-first account may be missing, without clobbering.
      def backfill!(user)
        changes = {}
        changes[:name] = @name if user.name.blank? && @name.present?
        changes[:confirmed_at] = Time.current if user.confirmed_at.blank? && @email_verified
        user.update!(changes) if changes.any?
      end
    end
  end
end
