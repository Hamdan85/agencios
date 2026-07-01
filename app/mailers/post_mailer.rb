# frozen_string_literal: true

# Publishing outcome emails to the ticket owner (assignee → creator fallback).
class PostMailer < ApplicationMailer
  def published(post:, recipient:)
    @post = post
    @recipient = recipient
    @ticket = post.ticket
    @provider = post.social_account.provider.to_s.titleize
    @ticket_url = "#{SystemConfig.app_host}/tickets/#{@ticket.id}"
    mail(to: recipient.email, subject: "Post publicado em #{@provider} ✅")
  end

  def failed(post:, recipient:, reason: nil)
    @post = post
    @recipient = recipient
    @ticket = post.ticket
    @provider = post.social_account.provider.to_s.titleize
    @reason = reason || post.failure_reason
    @ticket_url = "#{SystemConfig.app_host}/tickets/#{@ticket.id}"
    mail(to: recipient.email, subject: "Falha ao publicar em #{@provider}")
  end
end
