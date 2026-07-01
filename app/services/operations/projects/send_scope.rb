# frozen_string_literal: true

module Operations
  module Projects
    # Emails a read-only content-scope summary (one row per ticket: name,
    # type(s), target date) to whichever addresses the manager typed in —
    # not necessarily the client's registered email.
    class SendScope < Operations::Base
      def initialize(project:, recipients:)
        @project = project
        @recipients = Array(recipients).map(&:to_s).map(&:strip).compact_blank.uniq
      end

      def call
        raise Operations::Errors::Invalid, 'Informe pelo menos um destinatário.' if @recipients.empty?

        ProjectMailer.scope_summary(project: @project, recipients: @recipients).deliver_later
      end
    end
  end
end
