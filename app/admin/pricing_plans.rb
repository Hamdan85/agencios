# frozen_string_literal: true

ActiveAdmin.register PricingPlan do
  menu parent: I18n.t('admin.menu.pricing'), label: I18n.t('admin.pricing_plans.menu'), priority: 2

  permit_params :key, :name, :stripe_product_id, :stripe_lookup_key, :stripe_price_id,
                :stripe_annual_lookup_key, :stripe_annual_price_id,
                :price_cents, :annual_price_cents, :seats, :clients,
                :included_credits, :position, :active, :features_text

  config.sort_order = 'position_asc'

  # Force a re-sync (idempotent) — e.g. after editing a price directly in Stripe,
  # or to re-provision a plan that lost its Product/Price.
  action_item :sync_to_stripe, only: :show do
    link_to I18n.t('admin.pricing_plans.sync_action'), sync_to_stripe_admin_pricing_plan_path(resource),
            method: :post, data: { confirm: I18n.t('admin.pricing_plans.sync_confirm') }
  end

  member_action :sync_to_stripe, method: :post do
    Operations::Billing::SyncPlanToStripe.call(plan: resource)
    AdminAuditLog.record(staff_user: current_staff_user, action: 'sync_plan_to_stripe',
                         target: resource,
                         metadata: { price_cents: resource.price_cents, annual_price_cents: resource.annual_price_cents },
                         ip_address: request.remote_ip)
    redirect_to admin_pricing_plan_path(resource),
                notice: I18n.t('admin.pricing_plans.sync_notice', key: resource.key)
  rescue Vendors::Base::NotConfiguredError => e
    redirect_to admin_pricing_plan_path(resource), alert: I18n.t('admin.pricing_plans.not_configured', message: e.message)
  rescue StandardError => e
    redirect_to admin_pricing_plan_path(resource), alert: I18n.t('admin.pricing_plans.sync_failed', message: e.message)
  end

  index do
    selectable_column
    column :position
    column :key
    column :name
    column(I18n.t('admin.pricing_plans.col_monthly')) { |p| number_to_currency(p.price_cents / 100.0, unit: 'R$ ') }
    column(I18n.t('admin.pricing_plans.col_annual')) { |p| number_to_currency(Pricing.annual_price_cents_for(p.key) / 100.0, unit: 'R$ ') }
    column(I18n.t('admin.pricing_plans.col_included_credits'), &:included_credits)
    column :seats
    column :clients
    column(I18n.t('admin.pricing_plans.col_stripe_price')) { |p| p.stripe_price_id.presence || I18n.t('admin.pricing_plans.not_synced') }
    column :active
    actions
  end

  show do
    attributes_table do
      row :key
      row :name
      row(I18n.t('admin.pricing_plans.row_monthly')) { |p| number_to_currency(p.price_cents / 100.0, unit: 'R$ ') }
      row(I18n.t('admin.pricing_plans.row_annual')) { |p| number_to_currency(Pricing.annual_price_cents_for(p.key) / 100.0, unit: 'R$ ') }
      row :seats
      row :clients
      row :included_credits
      row(I18n.t('admin.pricing_plans.row_features')) { |p| ul { Array(p.features).each { |f| li f } } }
      row :stripe_product_id
      row :stripe_lookup_key
      row :stripe_price_id
      row :stripe_annual_price_id
      row :position
      row :active
      row :updated_at
    end
    para I18n.t('admin.pricing_plans.show_note')
  end

  form do |f|
    f.semantic_errors
    f.inputs I18n.t('admin.pricing_plans.plan_section') do
      para class: 'inline-hints' do
        span I18n.t('admin.pricing_plans.plan_section_hint')
      end
      f.input :key, hint: I18n.t('admin.pricing_plans.key_hint')
      f.input :name
      f.input :price_cents, label: I18n.t('admin.pricing_plans.price_cents_label')
      f.input :annual_price_cents,
              label: I18n.t('admin.pricing_plans.annual_price_cents_label'),
              hint: I18n.t('admin.pricing_plans.annual_price_cents_hint', percent: Pricing.annual_discount_percent)
      f.input :seats
      f.input :clients
      f.input :included_credits, label: I18n.t('admin.pricing_plans.included_credits_label')
      f.input :features_text, as: :text, label: I18n.t('admin.pricing_plans.features_text_label'), input_html: { rows: 8 }
    end
    f.inputs I18n.t('admin.pricing_plans.stripe_section') do
      f.input :stripe_product_id, hint: I18n.t('admin.pricing_plans.stripe_product_hint')
      f.input :stripe_lookup_key, hint: I18n.t('admin.pricing_plans.stripe_lookup_hint')
      f.input :stripe_price_id, label: I18n.t('admin.pricing_plans.stripe_price_id_label')
      f.input :stripe_annual_lookup_key, hint: I18n.t('admin.pricing_plans.stripe_annual_lookup_hint')
      f.input :stripe_annual_price_id, label: I18n.t('admin.pricing_plans.stripe_annual_price_id_label')
    end
    f.inputs I18n.t('admin.pricing_plans.display_section') do
      f.input :position
      f.input :active
    end
    f.actions
  end

  # Keep Stripe in step with the catalog: on every create/update, ensure the
  # Product + Prices exist and match (idempotent — a plain edit mints no new
  # Price). Controller hook, not an AR callback. A Stripe failure surfaces as a
  # flash but never loses the saved edit.
  after_save do |plan|
    next unless plan.persisted? && plan.valid?

    begin
      Operations::Billing::SyncPlanToStripe.call(plan: plan)
    rescue Vendors::Base::NotConfiguredError => e
      flash[:warning] = I18n.t('admin.pricing_plans.save_not_configured', message: e.message)
    rescue StandardError => e
      Rails.logger.error("[Admin::PricingPlans] Stripe sync failed for #{plan.key}: #{e.message}")
      flash[:error] = I18n.t('admin.pricing_plans.save_sync_failed', message: e.message)
    end

    AdminAuditLog.record(staff_user: current_staff_user, action: 'edit_pricing_plan',
                         target: plan, metadata: { changes: plan.saved_changes.keys },
                         ip_address: request.remote_ip)
  end
end
