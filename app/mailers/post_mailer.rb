# frozen_string_literal: true

# Publishing outcome emails to the ticket owner (assignee → creator fallback).
class PostMailer < ApplicationMailer
  def published(post:, recipient:)
    @post = post
    @recipient = recipient
    @ticket = post.ticket
    @provider = post.social_account.provider.to_s.titleize
    @ticket_url = "#{SystemConfig.app_host}/tickets/#{@ticket.id}"
    with_recipient_locale(recipient) do
      mail(to: recipient.email, subject: I18n.t('mailers.post.published.subject', provider: @provider))
    end
  end

  def failed(post:, recipient:, reason: nil)
    @post = post
    @recipient = recipient
    @ticket = post.ticket
    @provider = post.social_account.provider.to_s.titleize
    @reason = reason || post.failure_reason
    @ticket_url = "#{SystemConfig.app_host}/tickets/#{@ticket.id}"
    with_recipient_locale(recipient) do
      mail(to: recipient.email, subject: I18n.t('mailers.post.failed.subject', provider: @provider))
    end
  end
end
