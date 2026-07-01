# frozen_string_literal: true

require_relative 'mailer_preview_data'

# Preview at /rails/mailers/invoice_mailer
class InvoiceMailerPreview < ActionMailer::Preview
  def created
    InvoiceMailer.created(invoice: MailerPreviewData.invoice, payment_url: 'https://www.mercadopago.com.br/checkout/sample')
  end

  def paid
    InvoiceMailer.paid(invoice: MailerPreviewData.invoice)
  end

  def overdue
    InvoiceMailer.overdue(invoice: MailerPreviewData.invoice, payment_url: 'https://www.mercadopago.com.br/checkout/sample')
  end

  def canceled
    InvoiceMailer.canceled(invoice: MailerPreviewData.invoice)
  end
end
