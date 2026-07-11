# frozen_string_literal: true

require 'securerandom'

module Operations
  module Billing
    # Generates a hosted payment link for an invoice through its payment provider
    # and records (or refreshes) the Charge that holds it. When the client pays,
    # the provider's webhook reconciles the charge via Operations::Billing::
    # SyncPaymentStatus.
    #
    # Only Mercado Pago is wired today; Asaas, Stripe, Stone, … slot in behind the
    # `provider` switch without touching callers.
    #
    #   Operations::Billing::GeneratePaymentLink.call(invoice: invoice)
    class GeneratePaymentLink < Operations::Base
      DEFAULT_PROVIDER = 'mercado_pago'

      def initialize(invoice:, provider: DEFAULT_PROVIDER)
        @invoice = invoice
        @provider = provider.to_s
      end

      def call
        link = build_link
        upsert_charge(link)
      end

      private

      # Provider dispatch. Each branch returns a normalized link hash:
      # { provider:, preference_id:, payment_link: }.
      def build_link
        case @provider
        when 'mercado_pago' then mercado_pago_link
        else
          raise Operations::Errors::Invalid, I18n.t('operations.billing.unsupported_provider', provider: @provider)
        end
      end

      # Mercado Pago Checkout Pro preference — `init_point` is the payment link.
      # Falls back to a mock link when MP isn't configured, so the flow stays
      # demoable locally.
      def mercado_pago_link
        preference = Vendors::MercadoPago::Actions::CreatePreference.call(
          invoice: @invoice, payer: { email: @invoice.client.email }
        )
        {
          provider: 'mercado_pago',
          preference_id: preference['id']&.to_s,
          payment_link: preference['init_point'].presence || preference['sandbox_init_point']
        }
      rescue Vendors::Base::NotConfiguredError, Vendors::Base::Error => e
        Rails.logger.warn("[Billing::GeneratePaymentLink] Mercado Pago unavailable (#{e.message}) — mock link.")
        {
          provider: 'mercado_pago',
          preference_id: nil,
          payment_link: "https://www.mercadopago.com.br/checkout/v1/redirect?pref_id=MOCK-#{SecureRandom.hex(8)}"
        }
      end

      # Reuse the latest still-open charge (regenerating a link on the same
      # invoice), or open a fresh one once the previous attempt is settled.
      def upsert_charge(link)
        attrs = {
          provider: link[:provider],
          preference_id: link[:preference_id],
          payment_link: link[:payment_link],
          amount_cents: @invoice.amount_cents,
          status: 'pending'
        }

        charge = @invoice.latest_charge
        charge = nil if charge&.paid?

        if charge
          charge.update!(attrs)
          charge
        else
          @invoice.charges.create!(attrs.merge(workspace: @invoice.workspace))
        end
      end
    end
  end
end
