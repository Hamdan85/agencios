# frozen_string_literal: true

# Internal/product mail — no @brand_workspace, since a user's digest can span
# several agencies at once.
class DigestMailer < ApplicationMailer
  def daily_tickets(user:, tickets:)
    @user = user
    @tickets_by_workspace = tickets.group_by(&:workspace)
    @date = Date.current
    mail(to: user.email, subject: "Seus tickets de hoje — #{email_date(@date)}")
  end
end
