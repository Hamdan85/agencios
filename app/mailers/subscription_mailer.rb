# frozen_string_literal: true

# SaaS-billing emails (agencios charging the workspace via Stripe). These go to
# the workspace owner.
class SubscriptionMailer < ApplicationMailer
  PLAN_LABELS = { 'solo' => 'Solo', 'agencia' => 'Agência', 'enterprise' => 'Enterprise' }.freeze

  # Trial is about to end (customer.subscription.trial_will_end).
  def trial_ending(workspace:, subscription:)
    assign(workspace, subscription)
    mail(to: @owner.email, subject: 'Seu teste da agencios termina em breve')
  end

  # A charge failed (invoice.payment_failed → past_due).
  def payment_failed(workspace:, subscription:)
    assign(workspace, subscription)
    mail(to: @owner.email, subject: 'Falha no pagamento da sua assinatura agencios')
  end

  # Subscription was canceled (customer.subscription.deleted).
  def canceled(workspace:, subscription:)
    assign(workspace, subscription)
    mail(to: @owner.email, subject: 'Sua assinatura agencios foi cancelada')
  end

  private

  def assign(workspace, subscription)
    @workspace = workspace
    @subscription = subscription
    @owner = workspace.owner
    @plan_label = PLAN_LABELS[subscription&.plan.to_s] || subscription&.plan.to_s.humanize
    @billing_url = "#{SystemConfig.app_host}/assinatura"
  end
end
