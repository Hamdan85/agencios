# frozen_string_literal: true

ActiveAdmin.register PricingPlan do
  menu parent: 'Preços', label: 'Planos', priority: 2

  permit_params :key, :name, :stripe_product_id, :stripe_lookup_key, :stripe_price_id,
                :stripe_annual_lookup_key, :stripe_annual_price_id,
                :price_cents, :annual_price_cents, :usd_cents, :seats, :clients,
                :included_credits, :position, :active, :features_text

  config.sort_order = 'position_asc'

  # Refresh the cached display amounts from Stripe (Stripe = source of truth).
  action_item :sync_prices, only: :index do
    link_to 'Sincronizar preços do Stripe', sync_prices_admin_pricing_plans_path, method: :post
  end

  action_item :publish_to_stripe, only: :show do
    link_to 'Publicar preços no Stripe', publish_to_stripe_admin_pricing_plan_path(resource),
            method: :post,
            data: { confirm: 'Criar novos Prices (mensal + anual) no Stripe com estes valores? ' \
                             'Novos checkouts usarão o novo preço; assinantes atuais mantêm o antigo.' }
  end

  collection_action :sync_prices, method: :post do
    updated = Vendors::Stripe::Actions::SyncPlanPrices.call
    AdminAuditLog.record(staff_user: current_staff_user, action: 'sync_plan_prices',
                         metadata: { updated: updated }, ip_address: request.remote_ip)
    redirect_to admin_pricing_plans_path, notice: "#{updated} plano(s) sincronizado(s) com o Stripe."
  end

  # Push the edited amounts TO Stripe: creates new Prices (monthly + annual) with
  # the plan's lookup_key and archives the old ones. Affects NEW checkouts;
  # existing assinantes mantêm o preço atual (grandfathering).
  member_action :publish_to_stripe, method: :post do
    Vendors::Stripe::Actions::PublishPlanPrices.call(plan: resource)
    AdminAuditLog.record(staff_user: current_staff_user, action: 'publish_plan_to_stripe',
                         target: resource,
                         metadata: { price_cents: resource.price_cents, annual_price_cents: resource.annual_price_cents },
                         ip_address: request.remote_ip)
    redirect_to admin_pricing_plan_path(resource),
                notice: "Preços do plano #{resource.key} publicados no Stripe (mensal + anual). " \
                        'Novos checkouts já usam o novo valor; assinantes atuais mantêm o preço antigo.'
  rescue Vendors::Base::NotConfiguredError => e
    redirect_to admin_pricing_plan_path(resource), alert: "Stripe não configurado: #{e.message}"
  end

  index do
    selectable_column
    column :position
    column :key
    column :name
    column('Mensal (BRL)') { |p| number_to_currency(p.price_cents / 100.0, unit: 'R$ ') }
    column('Anual (BRL)') { |p| number_to_currency(Pricing.annual_price_cents_for(p.key) / 100.0, unit: 'R$ ') }
    column('Créditos inclusos', &:included_credits)
    column :seats
    column :clients
    column('Stripe lookup', &:stripe_lookup_key)
    column('Stripe price', &:stripe_price_id)
    column :active
    actions
  end

  show do
    attributes_table do
      row :key
      row :name
      row('Preço (BRL)') { |p| number_to_currency(p.price_cents / 100.0, unit: 'R$ ') }
      row('Preço (USD, display)') { |p| number_to_currency(p.usd_cents / 100.0, unit: 'US$ ') }
      row :seats
      row :clients
      row :included_credits
      row('Recursos') { |p| ul { Array(p.features).each { |f| li f } } }
      row :stripe_product_id
      row :stripe_lookup_key
      row :stripe_price_id
      row :position
      row :active
      row :updated_at
    end
  end

  form do |f|
    f.semantic_errors
    f.inputs 'Plano' do
      para class: 'inline-hints' do
        strong 'Atenção: '
        span 'editar o preço aqui NÃO altera o Stripe sozinho — é um rascunho de exibição. ' \
             'Depois de salvar, clique em “Publicar preços no Stripe” na página do plano para criar o Price novo.'
      end
      f.input :key, hint: 'Chave estável (solo/agencia/enterprise). Referenciada por Subscription#plan.'
      f.input :name
      f.input :price_cents, label: 'Preço MENSAL em centavos (BRL) — cacheado do Stripe'
      f.input :annual_price_cents,
              label: 'Preço ANUAL em centavos (BRL) — 0 = calcula 12× mensal − desconto',
              hint: 'Cacheado do Stripe quando provisionado; 0 usa o desconto anual da config.'
      f.input :usd_cents, label: 'Preço em centavos (USD, apenas display)'
      f.input :seats
      f.input :clients
      f.input :included_credits, label: 'Créditos mensais inclusos'
      f.input :features_text, as: :text, label: 'Recursos (um por linha)',
                              input_html: { rows: 8 }
    end
    f.inputs 'Stripe (fonte da verdade do valor cobrado)' do
      f.input :stripe_product_id, hint: 'ID estável do Product (mapeia assinaturas ao plano, resiste a troca de preço).'
      f.input :stripe_lookup_key,
              hint: 'lookup_key do Price MENSAL. Troque o preço criando um Price novo com transfer_lookup_key.'
      f.input :stripe_price_id, label: 'Stripe price id mensal (cacheado — preenchido pela sincronização)'
      f.input :stripe_annual_lookup_key, hint: 'lookup_key do Price ANUAL.'
      f.input :stripe_annual_price_id, label: 'Stripe price id anual (cacheado)'
    end
    f.inputs 'Exibição' do
      f.input :position
      f.input :active
    end
    f.actions
  end

  after_save do |plan|
    if plan.saved_changes? && plan.persisted?
      AdminAuditLog.record(staff_user: current_staff_user, action: 'edit_pricing_plan',
                           target: plan, metadata: { changes: plan.saved_changes.keys },
                           ip_address: request.remote_ip)
    end
  end
end
