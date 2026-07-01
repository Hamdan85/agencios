# frozen_string_literal: true

# Client-facing billing emails (the agency charging its client via Mercado Pago).
# These go to `invoice.client.email`; callers must guard a blank address.
class InvoiceMailer < ApplicationMailer
  # A new invoice was issued. `payment_url` is the Mercado Pago link when one has
  # already been generated (Operations::Billing::GeneratePaymentLink), else nil.
  def created(invoice:, payment_url: nil)
    assign(invoice)
    @payment_url = payment_url
    mail(to: @client.email, subject: "Nova cobrança da #{@workspace.name} — #{email_amount}")
  end

  # Payment confirmed — a receipt.
  def paid(invoice:)
    assign(invoice)
    mail(to: @client.email, subject: "Pagamento confirmado — #{email_amount}")
  end

  # Past-due reminder (dunning).
  def overdue(invoice:, payment_url: nil)
    assign(invoice)
    @payment_url = payment_url
    mail(to: @client.email, subject: "Cobrança em atraso — #{email_amount}")
  end

  # The invoice was canceled.
  def canceled(invoice:)
    assign(invoice)
    mail(to: @client.email, subject: "Cobrança cancelada — #{@workspace.name}")
  end

  private

  def assign(invoice)
    @invoice = invoice
    @client = invoice.client
    @workspace = invoice.workspace
  end

  def email_amount
    email_brl(@invoice.amount_cents)
  end
end
