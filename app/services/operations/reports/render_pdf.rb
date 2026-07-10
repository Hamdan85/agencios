# frozen_string_literal: true

module Operations
  module Reports
    # Renders a ready ProjectReport's deck to a branded PDF (agency logo/colors +
    # "powered by agencios.app"), caches it as the report's `pdf` attachment, and
    # returns the binary bytes. Re-rendered on demand; the attachment is replaced.
    class RenderPdf < Operations::Base
      def initialize(report:)
        @report = report
        @project = report.project
      end

      def call
        html = render_html
        bytes = Vendors::Render::Pdf.call(html: html)
        attach(bytes)
        bytes
      end

      private

      def render_html
        # The report is a CLIENT-facing artifact — render it in the client's
        # locale (falling back to the workspace default).
        I18n.with_locale(client_locale) do
          ApplicationController.render(
            template: 'reports/pdf',
            layout: 'report_pdf',
            assigns: { report: @report, data: @report.data || {}, brand: brand }
          )
        end
      end

      def client_locale
        code = @project.client&.locale.presence || @project.workspace&.locale
        I18n.available_locales.find { |l| l.to_s == code.to_s } || I18n.default_locale
      end

      def brand
        ws = @project.workspace
        client = @project.client
        {
          agency_name: ws.name,
          logo_url: logo_url(ws),
          primary_color: (client&.brand_primary_color.presence || ws.brand_primary_color).presence || '#7C3AED',
          secondary_color: ws.brand_secondary_color.presence
        }
      end

      def attach(bytes)
        @report.pdf.attach(
          io: StringIO.new(bytes),
          filename: "relatorio-#{@project.name.parameterize}.pdf",
          content_type: 'application/pdf'
        )
      rescue StandardError => e
        Rails.logger.warn("[Reports::RenderPdf] attach failed for report ##{@report.id}: #{e.message}")
      end

      def logo_url(ws)
        return nil unless ws.logo.attached?

        Rails.application.routes.url_helpers.rails_blob_url(ws.logo, host: SystemConfig.app_host)
      rescue StandardError
        nil
      end
    end
  end
end
