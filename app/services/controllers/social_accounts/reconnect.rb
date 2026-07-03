# frozen_string_literal: true

module Controllers
  module SocialAccounts
    # POST /social_accounts/:id/reconnect — actually VALIDATES the connection:
    # re-exchanges the stored token via the provider (Operations::Social::
    # RefreshToken). Only a successful exchange flips the account back to
    # `connected`; a dead token stays `needs_reauth` and the user is pointed to
    # the real OAuth reconnect flow instead of a green light that lies.
    class Reconnect < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        client = workspace.clients.find(@params[:client_id])
        account = client.social_accounts.find(@params[:id])

        Operations::Social::RefreshToken.call(social_account: account)
        account.reload

        unless account.status_connected?
          raise Operations::Errors::Invalid,
                'Não foi possível reativar com o token atual — reconecte a conta pelo fluxo de autorização da rede.'
        end

        { social_account: serialize(account, SocialAccountSerializer) }
      end
    end
  end
end
