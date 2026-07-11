# frozen_string_literal: true

# Alerts a workspace owner/admin that a credit-dependent action was blocked for
# lack of credits (e.g. a client asked for changes but the wallet is empty).
class CreditAlertMailer < ApplicationMailer
  def insufficient(workspace:, recipient:, required:, context: nil)
    @brand_workspace = workspace
    @required = required
    @context = context
    @url = app_url('/assinatura')
    with_recipient_locale(recipient) do
      mail(to: recipient.email, subject: I18n.t('mailers.credit_alert.insufficient.subject'))
    end
  end
end
