# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # OAuth steps 2–4 WITHOUT persisting anything: exchange the code for a
      # long-lived user token, resolve the user id, and list every Page the user
      # manages — each normalized with its (optional) linked Instagram business
      # account (instagram.md/facebook.md §4).
      #
      # The caller decides which Page to attach to the client (an agency user can
      # manage many Pages, one per client), then builds the SocialAccount attrs
      # via `AccountAttrsForPage`. This split exists so the connect flow can show
      # a Page picker before writing any account.
      #
      # Returns a Hash:
      #   {
      #     external_user_id:, user_access_token:, token_expires_at:, scopes:,
      #     pages: [ { "id", "name", "access_token", "tasks",
      #                "ig_id", "ig_username" }, ... ]
      #   }
      class Exchange
        def self.call(...) = new(...).call

        def initialize(code:, redirect_uri:, client: nil)
          @code = code
          @redirect_uri = redirect_uri
          @client = client || Vendors::Meta::Client.new
        end

        def call
          short_lived = ExchangeCodeForToken.call(
            code: @code, redirect_uri: @redirect_uri, client: @client
          )
          long_lived = ExchangeLongLivedToken.call(
            short_lived_token: short_lived['access_token'], client: @client
          )
          user_token = long_lived['access_token']
          me = @client.get('/me', params: { fields: 'id' }, token: user_token)

          {
            external_user_id: me['id'],
            user_access_token: user_token,
            token_expires_at: expiry_from(long_lived['expires_in']),
            scopes: AuthorizeUrl::SCOPES,
            pages: list_pages(user_token)
          }
        end

        private

        def list_pages(user_token)
          raw = Array(ListPages.call(user_access_token: user_token, client: @client)['data'])
          raw.map { |page| normalize_page(page) }
        end

        # Resolve the linked IG business account, falling back to an explicit
        # lookup when the me/accounts expansion didn't include it.
        def normalize_page(page)
          ig = page['instagram_business_account']
          if ig.nil? && page['access_token'].present?
            ig = GetLinkedInstagramAccount.call(
              page_id: page['id'],
              page_access_token: page['access_token'],
              client: @client
            )['instagram_business_account']
          end

          {
            'id' => page['id'],
            'name' => page['name'],
            'access_token' => page['access_token'],
            'tasks' => Array(page['tasks']),
            'ig_id' => ig&.dig('id').presence,
            'ig_username' => ig&.dig('username').presence
          }
        end

        def expiry_from(expires_in)
          seconds = expires_in.to_i
          return nil if seconds.zero?

          Time.current + seconds.seconds
        end
      end
    end
  end
end
