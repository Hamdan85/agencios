# frozen_string_literal: true

module Controllers
  module Billing
    # The SaaS plan catalog surfaced on the workspace's own subscription screen.
    module Plans
      ALL = [
        {
          key: "solo", name: "Solo", price_cents: 9_900, seats: 1,
          features: [
            "1 assento",
            "Quadro de produção completo",
            "Geração de criativos com cobrança por uso",
            "Integrações sociais diretas"
          ]
        },
        {
          key: "agencia", name: "Agência", price_cents: 29_900, seats: 20,
          features: [
            "Até 20 assentos",
            "Tudo do Solo",
            "Faturamento de clientes (Mercado Pago)",
            "Calendário e reuniões (Google)",
            "Relatórios e retrospectivas com IA"
          ]
        },
        {
          key: "enterprise", name: "Enterprise", price_cents: 99_900, seats: 9_999,
          features: [
            "Assentos ilimitados",
            "Tudo da Agência",
            "Suporte prioritário",
            "Onboarding dedicado",
            "Limites de uso personalizados"
          ]
        }
      ].freeze

      module_function

      def find(key)
        ALL.find { |plan| plan[:key] == key.to_s }
      end
    end
  end
end
