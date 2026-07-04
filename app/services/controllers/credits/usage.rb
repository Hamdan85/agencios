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
        trunc = GRANULARITY[range]

        {
          range: range,
          since: since.iso8601,
          granularity: trunc,
          totals: totals(since),
          by_kind: by_kind(since),
          series: series(since, trunc),
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

      # Credit spend AND generation activity bucketed over time for the trend
      # chart. Zero-filled across the whole range so the axis is continuous (never
      # a lonely bar or a blank card). Each point carries both `credits` (real
      # spend, from debits) and `generations` (activity count) so the chart can
      # fall back to plotting activity when a period spent 0 credits (e.g. only
      # free carousels, or a godfathered workspace). `trunc` is from a fixed
      # whitelist (GRANULARITY), never user input, so the interpolation is safe.
      def series(since, trunc)
        group = bucket_sql(trunc)
        spend = workspace.credit_transactions.debits
                         .where(created_at: since..)
                         .group(group).sum(:amount)
        counts = workspace.generations
                          .where(created_at: since..)
                          .group(group).count

        buckets(since, trunc).map do |bucket|
          {
            date: bucket.iso8601,
            credits: -spend.fetch(bucket, 0).to_i,
            generations: counts.fetch(bucket, 0)
          }
        end
      end

      # Groups by the truncated bucket in the APP timezone, cast to a Ruby `Date`,
      # so the grouped keys line up exactly with the `buckets` zero-fill (which is
      # also in local time). `created_at` is `timestamp WITHOUT time zone` holding
      # UTC, so it must first be tagged UTC (`AT TIME ZONE 'UTC'` → timestamptz)
      # and THEN converted to the app zone; a single conversion mis-reads the
      # naive UTC value as local and shifts the date by the offset (buckets past
      # ~21:00 UTC land on tomorrow and fall outside the range). `trunc` and the
      # zone are config-derived (never user input), so the interpolation is safe.
      def bucket_sql(trunc)
        zone = ActiveRecord::Base.connection.quote(Time.zone.tzinfo.name)
        Arel.sql("date_trunc('#{trunc}', (created_at AT TIME ZONE 'UTC') AT TIME ZONE #{zone})::date")
      end

      # The bucket start dates from `since` to today, aligned to Postgres
      # date_trunc boundaries (week → Monday, month → 1st) so they match the
      # grouped query keys exactly.
      def buckets(since, trunc)
        step, cursor = case trunc
                       when 'week'  then [1.week, since.to_date.beginning_of_week]
                       when 'month' then [1.month, since.to_date.beginning_of_month]
                       else [1.day, since.to_date]
                       end
        today = Date.current
        out = []
        while cursor <= today
          out << cursor
          cursor += step
        end
        out
      end

      # The generations log — filterable by kind/status and paginated. Listed from
      # the generations table so free carousels appear too; the debit (if any)
      # gives the credit cost. Returns `{ items:, meta: }` so the client can page
      # with confidence it's seeing the full history, not a silent top-N.
      def recent(since)
        scope = workspace.generations.where(created_at: since..)
        scope = scope.where(kind: @params[:kind]) if KINDS.include?(@params[:kind].to_s)
        scope = scope.where(status: @params[:status]) if Generation.statuses.key?(@params[:status].to_s)
        scope = scope.order(created_at: :desc)

        records, meta = paginate(scope, @params, default_per: 20, max_per: 20)
        spent_by_gen = workspace.credit_transactions.debits
                                .where(generation_id: records.map(&:id))
                                .group(:generation_id).sum(:amount)

        items = records.map do |g|
          {
            id: g.id,
            kind: g.kind,
            status: g.status,
            provider: g.provider,
            credits: -spent_by_gen.fetch(g.id, 0).to_i,
            created_at: g.created_at.iso8601
          }
        end
        { items: items, meta: meta }
      end
    end
  end
end
