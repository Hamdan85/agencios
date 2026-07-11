# frozen_string_literal: true

# Internal/product mail — no @brand_workspace, since a user's digest can span
# several agencies at once.
class DigestMailer < ApplicationMailer
  def daily_tickets(user:, tickets:)
    @user = user
    @tickets_by_workspace = tickets.group_by(&:workspace)
    @date = Date.current
    with_recipient_locale(user) do
      mail(to: user.email, subject: I18n.t('mailers.digest.daily_tickets.subject', date: email_date(@date)))
    end
  end
end
