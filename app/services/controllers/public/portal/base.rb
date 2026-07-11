# frozen_string_literal: true

module Controllers
  module Public
    # The login-less client central ("central do cliente"). The path token
    # (Client#approval_token) is the credential — one link per client, resolving
    # the same Client used by the approval portal. Every lookup goes through the
    # client's own projects, so a token only ever sees its own campaigns.
    module Portal
      # User-facing label for the campaign (project) status, as the client sees
      # it in the central. Rendered in the client's locale (the portal request
      # cycle resolves the client's locale).
      def self.status_label(status) = I18n.t("api.portal.campaign_status.#{status}")

      class Base < Controllers::Base
        def initialize(client:, params: {})
          @client = client
          @params = params
        end

        private

        # The client's campaigns visible in the central: everything except drafts
        # (unstarted planning). Active first, then the rest, newest within each.
        def visible_projects
          @client.projects.where.not(status: :draft)
        end

        def project!
          visible_projects.find(@params[:project_id])
        end

        def agency
          ws = @client.workspace
          {
            name: ws.name,
            primary_color: (@client.brand_primary_color.presence || ws.brand_primary_color).presence || '#7C3AED',
            logo_url: blob_url(ws.logo)
          }
        end

        def blob_url(attachment)
          return nil unless attachment&.attached?

          Rails.application.routes.url_helpers.rails_blob_url(attachment, host: SystemConfig.app_host)
        rescue StandardError
          nil
        end
      end
    end
  end
end
