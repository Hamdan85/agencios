# frozen_string_literal: true

module Api
  module V1
    # The signed-in user's own account (profile, avatar, password, e-mail) —
    # personal, not workspace-scoped. Editable behind the paywall (a user on a
    # lapsed workspace must still fix their profile), so the billing gate is
    # skipped. Confirming an e-mail change happens from the link in the e-mail,
    # so that one action is public.
    class AccountsController < BaseController
      skip_billing_gate
      allow_unauthenticated_access only: %i[confirm_email]

      def update   = render_ok(Controllers::Account::Update.call(params:))
      def password = render_ok(Controllers::Account::UpdatePassword.call(params:))
      def avatar   = render_ok(Controllers::Account::UpdateAvatar.call(params:))
      def email    = render_ok(Controllers::Account::RequestEmailChange.call(params:))

      def confirm_email = render_ok(Controllers::Account::ConfirmEmailChange.call(params:))

      # Google Calendar is personal — meetings live on the user's own calendar.
      def google_calendar_authorize_url = render_ok(Controllers::Account::GoogleCalendar::AuthorizeUrl.call)
      def google_calendar               = render_ok(Controllers::Account::GoogleCalendar::Disconnect.call)
    end
  end
end
