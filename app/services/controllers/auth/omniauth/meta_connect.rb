# frozen_string_literal: true

module Controllers
  module Auth
    module Omniauth
      # Shared Meta connect helpers used by the OAuth callback (which lists Pages)
      # and the page-selection step (which persists the chosen Page). The exchange
      # result — long-lived token + the user's Pages — is stashed in Rails.cache
      # under a random nonce between the two requests (both hit the same single
      # container, so the cache is shared).
      module MetaConnect
        CACHE_TTL = 10.minutes

        # Raised when the user asked to connect Instagram but the chosen Page has
        # no linked Instagram business account. The controller maps it to a
        # `?error=no_instagram` redirect with actionable copy in the popup.
        class InstagramRequired < Operations::Errors::Invalid; end

        private

        def cache_key(nonce) = "meta_connect:#{nonce}"

        # Build the SocialAccount attrs for the chosen Page and persist them.
        # Enforces an Instagram account when the user explicitly requested it.
        def persist_page!(client:, network:, context:, page:)
          builder = Vendors::Meta::Actions::AccountAttrsForPage.new(context: context, page: page)
          if network.to_s == "instagram" && !builder.instagram?
            raise InstagramRequired, "no_instagram"
          end

          builder.call.each do |attrs|
            Operations::Social::ConnectAccount.call(client: client, attrs: attrs)
          end
        end
      end
    end
  end
end
