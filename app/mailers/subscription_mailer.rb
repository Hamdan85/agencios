# frozen_string_literal: true

# SaaS-billing emails (agencios charging the workspace via Stripe). These go to
# the workspace owner.
class SubscriptionMailer < ApplicationMailer
  # Trial is about to end (customer.subscription.trial_will_end).
  def trial_ending(workspace:, subscription:)
    assign(workspace, subscription)
    with_recipient_locale(@owner) do
      resolve_plan_label
      mail(to: @owner.email, subject: I18n.t('mailers.subscription.trial_ending.subject'))
    end
  end

  # A charge failed (invoice.payment_failed → past_due).
  def payment_failed(workspace:, subscription:)
    assign(workspace, subscription)
    with_recipient_locale(@owner) do
      resolve_plan_label
      mail(to: @owner.email, subject: I18n.t('mailers.subscription.payment_failed.subject'))
    end
  end

  # Subscription was canceled (customer.subscription.deleted).
  def canceled(workspace:, subscription:)
    assign(workspace, subscription)
    with_recipient_locale(@owner) do
      resolve_plan_label
      mail(to: @owner.email, subject: I18n.t('mailers.subscription.canceled.subject'))
    end
  end

  private

  def assign(workspace, subscription)
    @workspace = workspace
    @subscription = subscription
    @owner = workspace.owner
    @billing_url = "#{SystemConfig.app_host}/assinatura"
  end

  def resolve_plan_label
    plan = @subscription&.plan.to_s
    @plan_label = I18n.t("mailers.subscription.plans.#{plan}", default: plan.humanize)
  end
end
