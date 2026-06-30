# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # Build the SocialAccount attrs to persist for ONE chosen Page, from an
      # `Exchange` result. Returns an Array: always a Facebook entry for the Page,
      # plus an Instagram entry when that Page has a linked IG business account.
      # `Operations::Social::ConnectAccount` persists each (instagram.md §4).
      class AccountAttrsForPage
        def self.call(...) = new(...).call

        # `context` is the Exchange result Hash; `page` is one of its normalized
        # page Hashes (string keys).
        def initialize(context:, page:)
          @context = context
          @page = page
        end

        def call
          accounts = [facebook_attrs]
          accounts << instagram_attrs if instagram?
          accounts
        end

        # Whether the chosen Page exposes a connectable Instagram business account.
        def instagram?
          @page["ig_id"].present?
        end

        private

        def base
          {
            external_user_id: @context[:external_user_id],
            user_access_token: @context[:user_access_token],
            token_expires_at: @context[:token_expires_at],
            scopes: @context[:scopes]
          }
        end

        def facebook_attrs
          base.merge(
            provider: :facebook,
            page_id: @page["id"],
            username: @page["name"],
            page_access_token: @page["access_token"]
          )
        end

        def instagram_attrs
          base.merge(
            provider: :instagram,
            page_id: @page["id"],
            ig_user_id: @page["ig_id"],
            username: @page["ig_username"],
            page_access_token: @page["access_token"]
          )
        end
      end
    end
  end
end
