# frozen_string_literal: true

# Singleton config: the credit-economy + trial knobs. The index just bounces to
# the single row's edit form.
ActiveAdmin.register PricingConfig do
  menu parent: 'Preços', label: 'Config (créditos & trial)', priority: 1

  actions :index, :edit, :update

  permit_params :trial_days, :annual_discount_percent, :credit_unit_cents, :margin_multiplier,
                :usd_brl, :video_usd_per_sec, :image_credits, :carousel_credits,
                :video_standard_credits_per_15s, :video_photoreal_credits_per_15s

  action_item :restore_defaults, only: :index do
    link_to 'Restaurar catálogo padrão', restore_defaults_admin_pricing_configs_path, method: :post,
                                                                                      data: { confirm: 'Cria planos/pacotes/config que estiverem faltando (não sobrescreve os existentes).' }
  end

  collection_action :restore_defaults, method: :post do
    Pricing.seed_defaults!
    AdminAuditLog.record(staff_user: current_staff_user, action: 'seed_pricing_defaults',
                         ip_address: request.remote_ip)
    redirect_to admin_pricing_configs_path, notice: 'Catálogo padrão garantido.'
  end

  controller do
    # Singleton: always edit the one row.
    def index
      redirect_to edit_admin_pricing_config_path(PricingConfig.first_or_create!)
    end
  end

  form do |f|
    f.semantic_errors
    f.inputs 'Trial e cobrança' do
      f.input :trial_days, label: 'Dias de trial (0 = sem trial)'
      f.input :annual_discount_percent,
              label: 'Desconto do plano anual (%)',
              hint: 'Aplicado sobre 12× o preço mensal para calcular o preço anual padrão.'
    end
    f.inputs 'Economia de créditos (cost-plus por operação)' do
      f.input :credit_unit_cents, label: 'Valor do crédito em centavos (BRL) — 100 = R$1'
      f.input :margin_multiplier,
              label: 'Markup sobre o custo (6,5 ⇒ ~80% líquido)',
              hint: 'Cada operação cobra markup × custo real do vendor. 6,5 cobre IOF + gateway + desconto do maior pacote.'
      f.input :usd_brl,
              label: 'Câmbio fixo USD→BRL (conservador)',
              hint: 'Use o spot + colchão (~10–15%) e revise mensalmente. NÃO é ao vivo — é preço fixo, reajustado por você (evita indexação cambial).'
      f.input :video_usd_per_sec,
              label: 'Custo estimado de vídeo por segundo (USD)',
              hint: 'Usado só para a ESTIMATIVA/hold antes de rodar; o custo real do vendor faz o true-up no fim.'
      f.input :image_credits, label: 'Créditos por imagem'
      f.input :carousel_credits, label: 'Créditos por carrossel (0 = incluso)'
    end
    f.actions
  end

  after_save do |cfg|
    if cfg.saved_changes? && cfg.persisted?
      AdminAuditLog.record(staff_user: current_staff_user, action: 'edit_pricing_config',
                           target: cfg, metadata: { changes: cfg.saved_changes.keys },
                           ip_address: request.remote_ip)
    end
  end
end
