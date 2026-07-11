# frozen_string_literal: true

# Client-facing billing emails (the agency charging its client via Mercado Pago).
# These go to `invoice.client.email`; callers must guard a blank address.
class InvoiceMailer < ApplicationMailer
  # A new invoice was issued. `payment_url` is the Mercado Pago link when one has
  # already been generated (Operations::Billing::GeneratePaymentLink), else nil.
  def created(invoice:, payment_url: nil)
    assign(invoice)
    @payment_url = payment_url
    with_recipient_locale(@client) do
      mail(to: @client.email,
           subject: I18n.t('mailers.invoice.created.subject', workspace: @workspace.name, amount: email_amount))
    end
  end

  # An explicit "here's the link" send — from the invoice list or the
  # creation success dialog. Distinct from `created` (the initial notice):
  # this can fire any time after, including a resend.
  def payment_link(invoice:, payment_url:)
    assign(invoice)
    @payment_url = payment_url
    with_recipient_locale(@client) do
      mail(to: @client.email,
           subject: I18n.t('mailers.invoice.payment_link.subject', workspace: @workspace.name, amount: email_amount))
    end
  end

  # Payment confirmed — a receipt.
  def paid(invoice:)
    assign(invoice)
    with_recipient_locale(@client) do
      mail(to: @client.email, subject: I18n.t('mailers.invoice.paid.subject', amount: email_amount))
    end
  end

  # Past-due reminder (dunning).
  def overdue(invoice:, payment_url: nil)
    assign(invoice)
    @payment_url = payment_url
    with_recipient_locale(@client) do
      mail(to: @client.email, subject: I18n.t('mailers.invoice.overdue.subject', amount: email_amount))
    end
  end

  # The invoice was canceled.
  def canceled(invoice:)
    assign(invoice)
    with_recipient_locale(@client) do
      mail(to: @client.email, subject: I18n.t('mailers.invoice.canceled.subject', workspace: @workspace.name))
    end
  end

  private

  def assign(invoice)
    @invoice = invoice
    @client = invoice.client
    @workspace = invoice.workspace
    @brand_workspace = @workspace
  end

  def email_amount
    email_brl(@invoice.amount_cents)
  end
end
