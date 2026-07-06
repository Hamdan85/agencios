# frozen_string_literal: true

module Operations
  module Autopilot
    # Prices a GO run BEFORE it starts: sums the credit cost of every creative it
    # will generate across the given tickets, checks the wallet, and — on a
    # shortfall — suggests the smallest credit pack(s) that would cover it. Also
    # runs eligibility on each ticket so a project GO can be blocked (and the
    # blockers named) when any ticket isn't fully auto-generatable.
    #
    # Uses the SAME Pricing.credits_for math the per-generation debit uses, so the
    # estimate lines up with what actually gets held (video reconciled to real
    # duration afterwards — only ever a small delta).
    class Estimate < Operations::Base
      def initialize(tickets:, workspace:)
        @tickets = Array(tickets)
        @workspace = workspace
      end

      def call
        rows = @tickets.map { |ticket| ticket_row(ticket) }
        blocking = rows.reject { |r| r[:eligible] }
        total = rows.sum { |r| r[:subtotal] }
        # Unlimited godfathered workspaces never debit (see Operations::Credits::Debit,
        # Controllers::Base#require_credits!, WorkspaceSerializer) — treat their balance
        # as infinite so the GO estimate never shows a false shortfall. `available: nil`
        # mirrors the serializer's "nil = unlimited" convention.
        unlimited = @workspace.godfathered? && !@workspace.credit_limited?
        available = @workspace.credits_available.to_i
        shortfall = unlimited ? 0 : [total - available, 0].max

        video_types = @tickets.flat_map(&:creative_types_list).select { |type| video_type?(type) }.uniq

        {
          eligible: blocking.empty?,
          unlimited: unlimited,
          total_credits: total,
          available: unlimited ? nil : available,
          shortfall: shortfall,
          packs_suggestion: shortfall.positive? ? suggested_packs(shortfall) : [],
          tickets: rows,
          blocking_tickets: blocking.map { |r| r.slice(:ticket_id, :title, :blocking_types) },
          # Video is never auto-generated in GO — it waits in production. Surfaced so
          # the GO dialog can warn the user (and excluded from total_credits below).
          has_pending_video: video_types.any?,
          pending_video_types: video_types
        }
      end

      private

      def ticket_row(ticket)
        elig = Operations::Autopilot::Eligibility.call(ticket: ticket)
        breakdown = ticket.creative_types_list.map { |type| type_cost(type) }
        {
          ticket_id: ticket.id,
          title: ticket.display_title,
          eligible: elig[:eligible],
          blocking_types: elig[:blocking_types],
          breakdown: breakdown,
          subtotal: breakdown.sum { |b| b[:credits] }
        }
      end

      def type_cost(type)
        spec = ::Creatives.spec_for(type)
        kind = spec&.dig(:kind)
        credits =
          case kind
          # Video is deferred to manual production — the GO run never generates it,
          # so it costs nothing here (and is flagged via has_pending_video).
          when 'video' then 0
          when 'image' then Pricing.credits_for(kind: :image)
          when 'carousel' then Pricing.credits_for(kind: :carousel)
          else 0
          end
        { type: type, kind: kind, credits: credits, deferred: kind == 'video' }
      end

      def video_type?(type) = ::Creatives.spec_for(type)&.dig(:kind) == 'video'

      # The cheapest single pack that covers the shortfall (or the largest pack if
      # none is big enough — the UI can suggest buying more than one).
      def suggested_packs(shortfall)
        packs = Pricing.credit_packs.sort_by { |p| p[:credits] }
        cover = packs.find { |p| p[:credits] >= shortfall }
        [cover || packs.last].compact.map { |p| p.slice(:key, :name, :credits, :price_cents) }
      end
    end
  end
end
