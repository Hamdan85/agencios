# frozen_string_literal: true

module Controllers
  module Connections
    # Account-level: the external apps (Claude connectors) the current user has
    # authorized via OAuth, one row per application with an active token.
    class Index < Base
      def call
        { connections: connections }
      end

      private

      def connections
        active_tokens
          .group_by(&:application_id)
          .map { |_app_id, tokens| present(tokens) }
      end

      def active_tokens
        Doorkeeper::AccessToken
          .where(resource_owner_id: user.id, revoked_at: nil)
          .includes(:application)
          .order(created_at: :desc)
          .reject(&:expired?)
      end

      def present(tokens)
        latest = tokens.first
        application = latest.application
        {
          id: latest.application_id,
          name: application&.name || "MCP Client",
          scopes: latest.scopes.to_a,
          dynamically_registered: application&.dynamically_registered || false,
          connected_at: tokens.map(&:created_at).min&.iso8601,
          last_authorized_at: latest.created_at.iso8601
        }
      end
    end
  end
end
