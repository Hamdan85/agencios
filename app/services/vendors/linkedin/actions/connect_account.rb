# frozen_string_literal: true

module Vendors
  module Linkedin
    module Actions
      # Uniform seam entrypoint: exchange the OAuth code, resolve the member
      # identity + admin orgs, and return the attributes to persist on a
      # SocialAccount. The seam's Operations::Social::ConnectAccount persists it.
      # See docs/integrations/linkedin.md §4–§5.
      class ConnectAccount
        def self.call(...) = new(...).call

        def initialize(code:, workspace:, redirect_uri:)
          @code = code
          @workspace = workspace
          @redirect_uri = redirect_uri
        end

        def call
          token = Vendors::Linkedin::Actions::ExchangeCode.call(
            code: @code, redirect_uri: @redirect_uri
          )
          access_token = token["access_token"]

          identity = Vendors::Linkedin::Actions::FetchUserInfo.call(access_token: access_token)
          org_urns = Vendors::Linkedin::Actions::FetchAdminOrganizations.call(access_token: access_token)

          {
            provider: :linkedin,
            external_user_id: identity[:member_id],
            username: identity[:member_name],
            user_access_token: access_token,
            refresh_token: token["refresh_token"],
            token_expires_at: expires_at(token["expires_in"]),
            scopes: scopes_array(token["scope"]),
            member_urn: identity[:member_urn],
            default_org_urn: org_urns.first
          }
        end

        private

        def expires_at(seconds)
          return nil if seconds.blank?

          Time.current + seconds.to_i.seconds
        end

        # LinkedIn returns scope comma- or space-delimited; normalize to an array.
        def scopes_array(scope)
          return [] if scope.blank?

          scope.split(/[,\s]+/).reject(&:blank?)
        end
      end
    end
  end
end
