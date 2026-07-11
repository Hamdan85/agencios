# frozen_string_literal: true

module Operations
  module Invoices
    # Opens a DRAFT invoice for payment (draft → open). The only entry into
    # `open` — a canceled or paid invoice never silently reopens.
    class Send < Operations::Base
      def initialize(invoice:)
        @invoice = invoice
      end

      def call
        unless @invoice.status_draft?
          raise Operations::Errors::Invalid,
                I18n.t('operations.invoices.only_draft_can_send')
        end

        @invoice.update!(status: :open)
        @invoice
      end
    end
  end
end
