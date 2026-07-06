# frozen_string_literal: true

module Operations
  module Autopilot
    # A client requested changes on a NON-VIDEO creative of a GO ticket. Regenerate
    # that single creative considering the feedback, supersede the old one, and
    # re-request the client's approval. Video is never regenerated here (it waits
    # in production — routed away by Operations::Approvals::RequestChanges).
    #
    # Credit-gated: if the wallet can't cover the regeneration, the workspace admins
    # are alerted and nothing is generated (the creative keeps its feedback for when
    # credits arrive).
    class Regenerate < Operations::Base
      def initialize(run:, creative:, feedback:)
        @run = run
        @creative = creative
        @feedback = feedback.to_s
        @ticket = creative.ticket
      end

      def call
        kind = spec_kind
        return if kind == 'video' # never regenerated automatically

        needed = credits_needed(kind)
        unless affordable?(needed)
          Operations::Credits::NotifyAdmins.call(
            workspace: workspace, required: needed,
            context: "Ajustes de #{@ticket.project.client&.name} em #{@ticket.display_title}"
          )
          return
        end

        generation = regenerate(kind)
        supersede!(generation)
        Operations::Approvals::RequestApproval.call(ticket: @ticket, sent_by: @run&.user)
        generation
      end

      private

      def workspace = @run&.workspace || @ticket.workspace

      def spec_kind = ::Creatives.spec_for(@creative.creative_type)&.dig(:kind)

      def credits_needed(kind)
        Pricing.credits_for(kind: kind.to_sym)
      end

      def affordable?(needed)
        return true if needed <= 0
        return true if workspace.godfathered? && !workspace.credit_limited?

        workspace.credits_available.to_i >= needed
      end

      def regenerate(kind)
        client_id = @ticket.project&.client_id
        case kind
        when 'carousel'
          Operations::Creatives::GenerateViralCarousel.call(
            ticket: @ticket, params: { client_id: client_id, revision_notes: @feedback }
          )
        when 'image'
          Operations::Creatives::GenerateImage.call(
            ticket: @ticket, creative_type: @creative.creative_type, client_id: client_id, revision_notes: @feedback
          )
        end
      end

      # Point the fresh creative at the one it replaces so approvable_creatives
      # excludes the old version.
      def supersede!(generation)
        fresh = generation&.creative
        return unless fresh

        fresh.update!(parent_id: @creative.id, version: @creative.version + 1)
      end
    end
  end
end
