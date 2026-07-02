# frozen_string_literal: true

module Controllers
  module Credits
    # GET /api/v1/credits/usage — how the workspace has actually spent its
    # credits, for the "Uso" tab on the subscription screen.
    #
    # Two truthful sources, deliberately kept apart:
    #   * `generations` — every generation run, the ACTIVITY count (carousels and
    #     godfathered runs included, even when they cost 0 credits).
    #   * `credit_transactions` debits — the real credit SPEND. A 0-credit
    #     generation (carousel) never records a debit, so credits spent on
    #     carousels is naturally 0. Video + image are the only paid kinds.
    class Usage < Base
      # range key → days back
      RANGES = { '7d' => 7, '30d' => 30, '90d' => 90, '12m' => 365 }.freeze
      # range key → Postgres date_trunc granularity for the trend series
      GRANULARITY = { '7d' => 'day', '30d' => 'day', '90d' => 'week', '12m' => 'month' }.freeze
      # ordered so the most expensive kind renders first
      KINDS = %w[video image carousel].freeze

      def initialize(params: {})
        @params = params
      end

      def call
        range = RANGES.key?(@params[:range].to_s) ? @params[:range].to_s : '30d'
        since = RANGES[range].days.ago.beginning_of_day

        {
          range: range,
          since: since.iso8601,
          granularity: GRANULARITY[range],
          totals: totals(since),
          by_kind: by_kind(since),
          series: series(since, GRANULARITY[range]),
          recent: recent(since),
          costs: Pricing.public_catalog[:credit_costs]
        }
      end

      private

      def totals(since)
        txns = workspace.credit_transactions.where(created_at: since..)
        {
          spent: -txns.debits.sum(:amount),
          granted_added: txns.where(kind: 'grant').sum(:amount),
          purchased_added: txns.where(kind: 'purchase').sum(:amount),
          generations: workspace.generations.where(created_at: since..).count
        }
      end

      # Per-kind activity count + credits actually spent. Credits come from the
      # ledger (only video/image ever debit); counts come from the generations
      # table so carousels still show up as "usado, incluso".
      def by_kind(since)
        gens = workspace.generations.where(created_at: since..)

        KINDS.map do |k|
          scope = gens.where(kind: k)
          spent = workspace.credit_transactions.debits
                           .joins(:generation)
                           .where(generations: { kind: Generation.kinds[k] })
                           .where(credit_transactions: { created_at: since.. })
                           .sum(:amount)
          {
            kind: k,
            count: scope.count,
            completed: scope.status_completed.count,
            failed: scope.status_failed.count,
            credits: -spent.to_i
          }
        end
      end

      # Credit spend bucketed over time for the trend chart. `trunc` is from a
      # fixed whitelist (GRANULARITY), never user input, so the interpolation is
      # safe.
      def series(since, trunc)
        raw = workspace.credit_transactions.debits
                       .where(created_at: since..)
                       .group(Arel.sql("date_trunc('#{trunc}', created_at)"))
                       .sum(:amount)

        raw.sort_by { |bucket, _| bucket }.map do |bucket, amount|
          { date: bucket.to_date.iso8601, credits: -amount.to_i }
        end
      end

      # The latest generations with the credits each one cost. Listed from the
      # generations table so free carousels appear too; the debit (if any) gives
      # the credit cost.
      def recent(since)
        gens = workspace.generations.where(created_at: since..)
                        .order(created_at: :desc).limit(12)
        spent_by_gen = workspace.credit_transactions.debits
                                .where(generation_id: gens.map(&:id))
                                .group(:generation_id).sum(:amount)

        gens.map do |g|
          {
            id: g.id,
            kind: g.kind,
            status: g.status,
            provider: g.provider,
            credits: -spent_by_gen.fetch(g.id, 0).to_i,
            created_at: g.created_at.iso8601
          }
        end
      end
    end
  end
end
