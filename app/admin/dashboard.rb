# frozen_string_literal: true

ActiveAdmin.register_page 'Dashboard' do
  menu priority: 1, label: proc { I18n.t('active_admin.dashboard') }

  content title: proc { I18n.t('active_admin.dashboard') } do
    month_scope = AiUsageLog.where(created_at: Time.zone.now.beginning_of_month..)

    div class: 'grid grid-cols-1 md:grid-cols-2 gap-4' do
      div do
        panel I18n.t('admin.dashboard.ai_cost_panel') do
          div do
            strong I18n.t('admin.dashboard.total')
            span number_to_currency(month_scope.total_cost_cents.to_f / 100.0, unit: 'US$ ')
          end
          table_for(month_scope.cost_by_provider.sort_by { |_, v| -v.to_f }) do
            column('Provider', &:first)
            column(I18n.t('admin.common.cost_usd')) { |row| number_to_currency(row.last.to_f / 100.0, unit: 'US$ ') }
          end
        end
      end

      div do
        panel I18n.t('admin.dashboard.top_operations_panel') do
          rows = month_scope.cost_by_operation.sort_by { |_, v| -v.to_f }.first(10)
          table_for rows do
            column('Operation', &:first)
            column(I18n.t('admin.common.cost_usd')) { |row| number_to_currency(row.last.to_f / 100.0, unit: 'US$ ') }
          end
        end
      end
    end

    panel I18n.t('admin.dashboard.recent_panel') do
      table_for AiUsageLog.recent_first.limit(15) do
        column(:created_at)
        column(:provider)
        column(:operation)
        column(:model)
        column(I18n.t('admin.common.cost_usd')) { |l| number_to_currency(l.estimated_cost_usd, unit: 'US$ ') }
      end
    end
  end
end
