# frozen_string_literal: true

ActiveAdmin.register PricingPack do
  menu parent: I18n.t('admin.menu.pricing'), label: I18n.t('admin.pricing_packs.menu'), priority: 3

  permit_params :key, :name, :price_cents, :credits, :position, :active

  config.sort_order = 'position_asc'

  index do
    selectable_column
    column :position
    column :key
    column :name
    column(I18n.t('admin.pricing_packs.col_price')) { |p| number_to_currency(p.price_cents / 100.0, unit: 'R$ ') }
    column :credits
    column(I18n.t('admin.pricing_packs.col_price_per_credit')) { |p| number_to_currency(p.price_cents / 100.0 / p.credits, unit: 'R$ ', precision: 3) }
    column :active
    actions
  end

  form do |f|
    f.semantic_errors
    f.inputs I18n.t('admin.pricing_packs.pack_section') do
      f.input :key
      f.input :name
      f.input :price_cents, label: I18n.t('admin.pricing_packs.price_cents_label')
      f.input :credits, label: I18n.t('admin.pricing_packs.credits_label')
      f.input :position
      f.input :active
    end
    f.actions
  end

  after_save do |pack|
    if pack.saved_changes? && pack.persisted?
      AdminAuditLog.record(staff_user: current_staff_user, action: 'edit_pricing_pack',
                           target: pack, metadata: { changes: pack.saved_changes.keys },
                           ip_address: request.remote_ip)
    end
  end
end
