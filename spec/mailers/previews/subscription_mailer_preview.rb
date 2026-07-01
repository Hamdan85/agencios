# frozen_string_literal: true

require_relative 'mailer_preview_data'

# Preview at /rails/mailers/subscription_mailer
class SubscriptionMailerPreview < ActionMailer::Preview
  def trial_ending
    SubscriptionMailer.trial_ending(workspace: MailerPreviewData.workspace,
                                    subscription: MailerPreviewData.subscription)
  end

  def payment_failed
    SubscriptionMailer.payment_failed(workspace: MailerPreviewData.workspace,
                                      subscription: MailerPreviewData.subscription)
  end

  def canceled
    SubscriptionMailer.canceled(workspace: MailerPreviewData.workspace, subscription: MailerPreviewData.subscription)
  end
end
