# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # Uniform seam entrypoint — exchange the OAuth code, derive a long-lived
      # user token + non-expiring Page token, resolve the linked Instagram
      # business account, and return SocialAccount attrs to persist
      # (instagram.md §4 / facebook.md §4). One pass connects BOTH networks.
      #
      # Returns an Array of attribute Hashes (one per connectable network found):
      # a Facebook entry for the chosen Page, and an Instagram entry when that
      # Page has a linked IG business account. The seam's
      # Operations::Social::ConnectAccount persists them.
      class ConnectAccount
        def self.call(...) = new(...).call

        def initialize(code:, workspace:, redirect_uri:, page_id: nil, client: nil)
          @code = code
          @workspace = workspace
          @redirect_uri = redirect_uri
          @page_id = page_id
          @client = client || Vendors::Meta::Client.new
        end

        def call
          short_lived = ExchangeCodeForToken.call(
            code: @code, redirect_uri: @redirect_uri, client: @client
          )
          short_token = short_lived["access_token"]

          long_lived = ExchangeLongLivedToken.call(
            short_lived_token: short_token, client: @client
          )
          user_token = long_lived["access_token"]
          expires_at = expiry_from(long_lived["expires_in"])

          me = @client.get("/me", params: { fields: "id" }, token: user_token)
          external_user_id = me["id"]

          pages = Array(ListPages.call(user_access_token: user_token, client: @client)["data"])
          page = pick_page(pages)
          raise Vendors::Base::Error, "Nenhuma Página do Facebook encontrada." if page.nil?

          base = {
            external_user_id:,
            user_access_token: user_token,
            token_expires_at: expires_at,
            scopes: AuthorizeUrl::SCOPES
          }

          accounts = [facebook_attrs(base, page)]
          ig = instagram_attrs(base, page, user_token)
          accounts << ig if ig
          accounts
        end

        private

        # Prefer an explicitly requested Page; otherwise the first one whose tasks
        # include CREATE_CONTENT (facebook.md §9), else the first Page.
        def pick_page(pages)
          return pages.find { |p| p["id"] == @page_id } || pages.first if @page_id

          pages.find { |p| Array(p["tasks"]).include?("CREATE_CONTENT") } || pages.first
        end

        def facebook_attrs(base, page)
          base.merge(
            provider: :facebook,
            page_id: page["id"],
            username: page["name"],
            page_access_token: page["access_token"]
          )
        end

        def instagram_attrs(base, page, user_token)
          ig = page["instagram_business_account"]
          # Fall back to an explicit lookup if me/accounts didn't expand it.
          if ig.nil? && page["access_token"].present?
            ig = GetLinkedInstagramAccount.call(
              page_id: page["id"],
              page_access_token: page["access_token"],
              client: @client
            )["instagram_business_account"]
          end
          return nil if ig.nil? || ig["id"].blank?

          base.merge(
            provider: :instagram,
            page_id: page["id"],
            ig_user_id: ig["id"],
            username: ig["username"],
            page_access_token: page["access_token"]
          )
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
