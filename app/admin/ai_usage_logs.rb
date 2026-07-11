# frozen_string_literal: true

module AiUsageChart
  DAYS_WINDOW = 30 unless defined?(DAYS_WINDOW)

  def self.palette
    %w[#6366f1 #10b981 #f59e0b #ef4444 #8b5cf6 #06b6d4 #ec4899 #84cc16 #f97316 #64748b]
  end

  def self.html(scoped)
    days = ((Time.zone.today - (DAYS_WINDOW - 1))..Time.zone.today).to_a
    data = daily_data(scoped, days.first)

    op_totals = Hash.new { |h, k| h[k] = { cost: 0.0, calls: 0, input: 0, output: 0 } }
    data.each_value do |ops|
      ops.each do |op, seg|
        total = op_totals[op]
        total[:cost]   += seg[:cost]
        total[:calls]  += seg[:calls]
        total[:input]  += seg[:input]
        total[:output] += seg[:output]
      end
    end

    if op_totals.empty?
      return %(<p style="color:#999;margin:0">#{esc(I18n.t('admin.ai_usage.chart.empty', days: DAYS_WINDOW))}</p>)
    end

    operations = op_totals.sort_by { |_, t| -t[:cost] }.map(&:first)
    colors     = operations.each_with_index.to_h { |op, i| [op, palette[i % palette.size]] }

    svg(days, data, operations, colors) + legend(operations, colors, op_totals)
  end

  def self.daily_data(scoped, first_day)
    tz        = ActiveRecord::Base.connection.quote(Time.zone.tzinfo.identifier)
    date_expr = Arel.sql("DATE(created_at AT TIME ZONE 'UTC' AT TIME ZONE #{tz})")

    rows = scoped.where(created_at: first_day.beginning_of_day..)
                 .group(date_expr, :operation)
                 .pluck(date_expr, :operation,
                        Arel.sql('COUNT(*)'),
                        Arel.sql('COALESCE(SUM(input_tokens), 0)'),
                        Arel.sql('COALESCE(SUM(cache_creation_input_tokens), 0)'),
                        Arel.sql('COALESCE(SUM(cache_read_input_tokens), 0)'),
                        Arel.sql('COALESCE(SUM(output_tokens), 0)'),
                        Arel.sql('COALESCE(SUM(cost_cents), 0)'))

    data = Hash.new { |h, k| h[k] = {} }
    rows.each do |day, op, calls, input, cache_write, cache_read, output, cost|
      seg = data[day.to_date][op] ||= { cost: 0.0, calls: 0, input: 0, output: 0 }
      seg[:cost]   += cost.to_f
      seg[:calls]  += calls
      seg[:input]  += input + cache_write + cache_read
      seg[:output] += output
    end
    data
  end

  def self.svg(days, data, operations, colors)
    width = 960
    height = 280
    m_left = 64
    m_right = 12
    m_top = 14
    m_bot = 30
    plot_w = width - m_left - m_right
    plot_h = height - m_top - m_bot
    slot   = plot_w.to_f / days.size
    bar_w  = [slot * 0.68, 2].max

    day_max = days.map { |d| (data[d] || {}).values.sum { |s| s[:cost] } }.max
    ymax    = nice_ceil(day_max.positive? ? day_max : 1)

    parts = [%(<svg viewBox="0 0 #{width} #{height}" width="100%" style="display:block;font-family:inherit">)]

    [0.0, 0.25, 0.5, 0.75, 1.0].each do |fraction|
      y = (m_top + plot_h * (1 - fraction)).round(1)
      parts << %(<line x1="#{m_left}" y1="#{y}" x2="#{width - m_right}" y2="#{y}" stroke="#e8e8e8" stroke-width="1"/>)
      parts << %(<text x="#{m_left - 8}" y="#{y + 3}" text-anchor="end" font-size="10" fill="#999">#{usd(ymax * fraction)}</text>)
    end

    days.each_with_index do |day, i|
      x        = (m_left + i * slot + (slot - bar_w) / 2).round(1)
      y_cursor = m_top + plot_h.to_f

      operations.each do |op|
        seg = data[day][op] or next
        seg_h = [plot_h * (seg[:cost] / ymax), 1.0].max
        y_cursor -= seg_h
        tooltip = "#{day.strftime('%d/%m')} · #{esc(op)} — #{seg[:calls]} #{I18n.t('admin.ai_usage.chart.calls')}&#10;" \
                  "#{tokens(seg[:input])} #{I18n.t('admin.ai_usage.chart.input_tokens')} · #{tokens(seg[:output])} #{I18n.t('admin.ai_usage.chart.output')}&#10;#{usd(seg[:cost])}"
        parts << %(<rect x="#{x}" y="#{y_cursor.round(2)}" width="#{bar_w.round(2)}" height="#{seg_h.round(2)}" fill="#{colors[op]}" rx="1"><title>#{tooltip}</title></rect>)
      end

      if (i % 5).zero? || i == days.size - 1
        parts << %(<text x="#{(x + bar_w / 2).round(1)}" y="#{height - m_bot + 14}" text-anchor="middle" font-size="10" fill="#999">#{day.strftime('%d/%m')}</text>)
      end
    end

    parts << '</svg>'
    parts.join
  end

  def self.legend(operations, colors, op_totals)
    totals = op_totals.values
    summary = %(<p style="margin:10px 0 4px;font-size:12px;color:#555">) +
              %(<strong>#{esc(I18n.t('admin.ai_usage.chart.period_total'))} #{usd(totals.sum { |t| t[:cost] })}</strong> · ) +
              %(#{totals.sum { |t| t[:calls] }} #{I18n.t('admin.ai_usage.chart.calls')} · ) +
              %(#{tokens(totals.sum { |t| t[:input] })} #{I18n.t('admin.ai_usage.chart.input_tokens')} · #{tokens(totals.sum do |t|
                t[:output]
              end)} #{I18n.t('admin.ai_usage.chart.output')}</p>)

    items = operations.map do |op|
      t = op_totals[op]
      "<span style=\"display:inline-flex;align-items:center;gap:6px\"><span style=\"width:10px;height:10px;border-radius:3px;background:#{colors[op]};display:inline-block\"></span><span><strong>#{esc(op)}</strong> · #{t[:calls]} #{I18n.t('admin.ai_usage.chart.calls')} · #{usd(t[:cost])}</span></span>"
    end

    summary + %(<div style="display:flex;flex-wrap:wrap;gap:6px 18px;font-size:12px;color:#555">#{items.join}</div>)
  end

  def self.nice_ceil(value)
    exponent = 10.0**Math.log10(value).floor
    [1, 2, 2.5, 5, 10].map { |m| m * exponent }.find { |n| n >= value }
  end

  # AI costs are often fractions of a cent (cheap models), so 2 decimals renders
  # them as "US$ 0.00". Show enough precision to reveal sub-cent spend.
  def self.usd(cents)
    dollars = cents.to_f / 100.0
    fmt = if dollars.zero? || dollars.abs >= 0.01 then 'US$ %.2f'
          elsif dollars.abs >= 0.0001 then 'US$ %.4f'
          else 'US$ %.6f'
          end
    format(fmt, dollars)
  end

  def self.tokens(count)
    count = count.to_i
    return count.to_s if count < 1_000

    count < 1_000_000 ? format('%.1fk', count / 1_000.0) : format('%.2fM', count / 1_000_000.0)
  end

  def self.esc(text) = CGI.escapeHTML(text.to_s)
end

module ActiveAdmin
  module Views
    class IndexAsTableWithChart < IndexAsTable
      def build(page_presenter, collection)
        scoped = collection.except(:select, :order, :limit, :offset)
        panel I18n.t('admin.ai_usage.chart.panel_title', days: AiUsageChart::DAYS_WINDOW) do
          text_node AiUsageChart.html(scoped).html_safe
        end
        super
      end
    end
  end
end

ActiveAdmin.register AiUsageLog do
  menu parent: I18n.t('admin.menu.platform'), label: I18n.t('admin.ai_usage.menu'), priority: 1
  actions :index, :show

  filter :workspace
  filter :provider, as: :select, collection: AiUsageLog::PROVIDERS
  filter :operation
  filter :model
  filter :subject_type
  filter :created_at

  scope :all, default: true
  scope(I18n.t('admin.ai_usage.scope_today')) { |s| s.where(created_at: Time.zone.now.beginning_of_day..) }
  scope(I18n.t('admin.ai_usage.scope_7d')) { |s| s.where(created_at: 7.days.ago..) }
  scope(I18n.t('admin.ai_usage.scope_30d')) { |s| s.where(created_at: 30.days.ago..) }
  scope(I18n.t('admin.ai_usage.scope_month')) { |s| s.where(created_at: Time.zone.now.beginning_of_month..) }

  index as: :table_with_chart do
    column :created_at
    column :workspace
    column :provider
    column :operation
    column :model
    column(I18n.t('admin.ai_usage.col_tokens')) { |l| "#{l.input_tokens} / #{l.output_tokens}" }
    column(I18n.t('admin.ai_usage.col_units')) { |l| l.units.to_f.zero? ? '—' : "#{l.units} #{l.unit_kind}" }
    column(I18n.t('admin.common.cost_usd')) { |l| AiUsageChart.usd(l.cost_cents) }
    column(I18n.t('admin.ai_usage.col_subject')) { |l| l.subject_type ? "#{l.subject_type}##{l.subject_id}" : '—' }
  end

  show do
    attributes_table do
      row :id
      row :workspace
      row :user
      row :provider
      row :operation
      row :model
      row(I18n.t('admin.ai_usage.col_subject')) { |l| l.subject_type ? "#{l.subject_type}##{l.subject_id}" : '—' }
      row :input_tokens
      row :output_tokens
      row :cache_creation_input_tokens
      row :cache_read_input_tokens
      row :unit_kind
      row :units
      row(I18n.t('admin.common.cost_usd')) { |l| AiUsageChart.usd(l.cost_cents) }
      row :created_at
    end
  end

  sidebar I18n.t('admin.ai_usage.sidebar_title'), only: :index do
    scoped = collection.except(:select, :order, :limit, :offset)
    total  = scoped.total_cost_cents.to_f
    by_provider  = scoped.cost_by_provider
    by_operation = scoped.cost_by_operation.sort_by { |_, v| -v.to_f }.first(8)

    div do
      strong I18n.t('admin.ai_usage.sidebar_total')
      span AiUsageChart.usd(total)
    end
    hr
    strong I18n.t('admin.ai_usage.sidebar_by_provider')
    ul do
      by_provider.each do |provider, cents|
        li "#{provider}: #{AiUsageChart.usd(cents)}"
      end
    end
    hr
    strong I18n.t('admin.ai_usage.sidebar_top_operations')
    ul do
      by_operation.each do |operation, cents|
        li "#{operation}: #{AiUsageChart.usd(cents)}"
      end
    end
  end
end
