# frozen_string_literal: true

# i18n rollout: existing PricingPlan/PricingPack rows were seeded with rendered
# pt-BR feature bullets + names. The code now stores i18n KEYS (localized at read
# time via Pricing#localize_features / #localize_name). This backfills the seeded
# rows to keys — but ONLY when a row still holds the exact original default text,
# so an operator's custom edits are never overwritten (they stay raw data).
class LocalizePricingCatalogCopy < ActiveRecord::Migration[8.1]
  # The original seeded pt-BR feature arrays, keyed by plan key → the key array
  # that replaces them.
  PLAN_FEATURE_MIGRATION = {
    'solo' => {
      old: ['2 assentos', 'Até 3 clientes', 'Quadro de produção completo',
            'Legendas e textos com IA inclusos',
            '40 créditos/mês para vídeos, imagens e carrosséis', 'Integrações sociais diretas'],
      new: %w[models.pricing.features.solo.seats models.pricing.features.solo.clients
              models.pricing.features.solo.board models.pricing.features.solo.ai_text
              models.pricing.features.solo.credits models.pricing.features.solo.social]
    },
    'agencia' => {
      old: ['Até 20 assentos', 'Até 25 clientes', 'Tudo do Solo',
            '200 créditos/mês para vídeos, imagens e carrosséis',
            'Faturamento de clientes (Mercado Pago)', 'Calendário e reuniões (Google)',
            'Aprovações de cliente e relatórios com IA'],
      new: %w[models.pricing.features.agencia.seats models.pricing.features.agencia.clients
              models.pricing.features.agencia.all_solo models.pricing.features.agencia.credits
              models.pricing.features.agencia.billing models.pricing.features.agencia.calendar
              models.pricing.features.agencia.approvals]
    },
    'enterprise' => {
      old: ['Assentos ilimitados', 'Clientes ilimitados', 'Tudo da Agência',
            '600 créditos/mês para vídeos, imagens e carrosséis', 'White-label e SSO',
            'Suporte prioritário e onboarding dedicado'],
      new: %w[models.pricing.features.enterprise.seats models.pricing.features.enterprise.clients
              models.pricing.features.enterprise.all_agencia models.pricing.features.enterprise.credits
              models.pricing.features.enterprise.white_label models.pricing.features.enterprise.support]
    }
  }.freeze

  # Names (plan + pack) need NO data migration — Pricing#localize_name resolves
  # models.pricing.names.<key> by KEY, so the stored `name` is only a fallback.
  # Only feature bullets are matched by string, hence this backfill.

  def up
    return unless table_exists?(:pricing_plans)

    PricingPlan.reset_column_information
    PLAN_FEATURE_MIGRATION.each do |key, map|
      plan = PricingPlan.find_by(key: key)
      next unless plan
      # Only migrate un-customized rows (exact match on the original defaults).
      next unless Array(plan.features).map(&:to_s) == map[:old]

      plan.update_columns(features: map[:new])
    end
  end

  def down
    return unless table_exists?(:pricing_plans)

    PricingPlan.reset_column_information
    PLAN_FEATURE_MIGRATION.each do |key, map|
      plan = PricingPlan.find_by(key: key)
      next unless plan
      next unless Array(plan.features).map(&:to_s) == map[:new]

      plan.update_columns(features: map[:old])
    end
  end
end
