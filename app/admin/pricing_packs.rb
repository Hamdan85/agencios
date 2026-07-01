# frozen_string_literal: true

ActiveAdmin.register PricingPack do
  menu parent: 'Preços', label: 'Pacotes de crédito', priority: 3

  permit_params :key, :name, :price_cents, :credits, :position, :active

  config.sort_order = 'position_asc'

  index do
    selectable_column
    column :position
    column :key
    column :name
    column('Preço (BRL)') { |p| number_to_currency(p.price_cents / 100.0, unit: 'R$ ') }
    column :credits
    column('R$/crédito') { |p| number_to_currency(p.price_cents / 100.0 / p.credits, unit: 'R$ ', precision: 3) }
    column :active
    actions
  end

  form do |f|
    f.semantic_errors
    f.inputs 'Pacote de crédito' do
      f.input :key
      f.input :name
      f.input :price_cents, label: 'Preço em centavos (BRL)'
      f.input :credits, label: 'Créditos concedidos (com bônus de volume)'
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
