# frozen_string_literal: true

ActiveAdmin.register PricingPlan do
  menu parent: 'Preços', label: 'Planos', priority: 2

  permit_params :key, :name, :stripe_product_id, :stripe_lookup_key, :stripe_price_id,
                :stripe_annual_lookup_key, :stripe_annual_price_id,
                :price_cents, :annual_price_cents, :seats, :clients,
                :included_credits, :position, :active, :features_text

  config.sort_order = 'position_asc'

  # Force a re-sync (idempotent) — e.g. after editing a price directly in Stripe,
  # or to re-provision a plan that lost its Product/Price.
  action_item :sync_to_stripe, only: :show do
    link_to 'Sincronizar com o Stripe', sync_to_stripe_admin_pricing_plan_path(resource),
            method: :post, data: { confirm: 'Garante o Product + Prices (mensal + anual) no Stripe com estes valores.' }
  end

  member_action :sync_to_stripe, method: :post do
    Operations::Billing::SyncPlanToStripe.call(plan: resource)
    AdminAuditLog.record(staff_user: current_staff_user, action: 'sync_plan_to_stripe',
                         target: resource,
                         metadata: { price_cents: resource.price_cents, annual_price_cents: resource.annual_price_cents },
                         ip_address: request.remote_ip)
    redirect_to admin_pricing_plan_path(resource),
                notice: "Plano #{resource.key} sincronizado com o Stripe (mensal + anual). " \
                        'Novos checkouts já usam o novo valor; assinantes atuais mantêm o preço antigo.'
  rescue Vendors::Base::NotConfiguredError => e
    redirect_to admin_pricing_plan_path(resource), alert: "Stripe não configurado: #{e.message}"
  rescue StandardError => e
    redirect_to admin_pricing_plan_path(resource), alert: "Falha ao sincronizar com o Stripe: #{e.message}"
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
    column('Stripe price') { |p| p.stripe_price_id.presence || '— não sincronizado' }
    column :active
    actions
  end

  show do
    attributes_table do
      row :key
      row :name
      row('Preço mensal (BRL)') { |p| number_to_currency(p.price_cents / 100.0, unit: 'R$ ') }
      row('Preço anual (BRL)') { |p| number_to_currency(Pricing.annual_price_cents_for(p.key) / 100.0, unit: 'R$ ') }
      row :seats
      row :clients
      row :included_credits
      row('Recursos') { |p| ul { Array(p.features).each { |f| li f } } }
      row :stripe_product_id
      row :stripe_lookup_key
      row :stripe_price_id
      row :stripe_annual_price_id
      row :position
      row :active
      row :updated_at
    end
    para 'Salvar um plano sincroniza o Product + Prices (mensal e anual) no Stripe automaticamente. ' \
         'Uma mudança de preço cria um Price novo e arquiva o antigo (assinantes atuais mantêm o preço).'
  end

  form do |f|
    f.semantic_errors
    f.inputs 'Plano (fonte da verdade do preço)' do
      para class: 'inline-hints' do
        span 'Ao salvar, os preços são publicados no Stripe automaticamente (um Price novo por mudança de valor). ' \
             'O valor definido aqui é o que o cliente paga.'
      end
      f.input :key, hint: 'Chave estável (solo/agencia/enterprise). Referenciada por Subscription#plan.'
      f.input :name
      f.input :price_cents, label: 'Preço MENSAL em centavos (BRL)'
      f.input :annual_price_cents,
              label: 'Preço ANUAL em centavos (BRL) — 0 = calcula 12× mensal − desconto',
              hint: "0 usa o desconto anual fixo (#{Pricing.annual_discount_percent}%)."
      f.input :seats
      f.input :clients
      f.input :included_credits, label: 'Créditos mensais inclusos'
      f.input :features_text, as: :text, label: 'Recursos (um por linha)', input_html: { rows: 8 }
    end
    f.inputs 'Stripe (preenchido automaticamente pela sincronização)' do
      f.input :stripe_product_id, hint: 'ID do Product (criado/atualizado ao salvar).'
      f.input :stripe_lookup_key, hint: 'lookup_key do Price MENSAL (estável — transferido para o novo Price).'
      f.input :stripe_price_id, label: 'Stripe price id mensal (cacheado)'
      f.input :stripe_annual_lookup_key, hint: 'lookup_key do Price ANUAL.'
      f.input :stripe_annual_price_id, label: 'Stripe price id anual (cacheado)'
    end
    f.inputs 'Exibição' do
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
      flash[:warning] = "Plano salvo, mas o Stripe não está configurado (#{e.message}) — não sincronizado."
    rescue StandardError => e
      Rails.logger.error("[Admin::PricingPlans] Stripe sync failed for #{plan.key}: #{e.message}")
      flash[:error] = "Plano salvo, mas a sincronização com o Stripe falhou: #{e.message}"
    end

    AdminAuditLog.record(staff_user: current_staff_user, action: 'edit_pricing_plan',
                         target: plan, metadata: { changes: plan.saved_changes.keys },
                         ip_address: request.remote_ip)
  end
end
