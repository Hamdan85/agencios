# frozen_string_literal: true

require 'rails_helper'

# The invoice status machine: transitions only through their dedicated ops
# (Send / Cancel / MarkPaid), plain edits guarded by Update, and a canceled
# invoice that can never be resurrected by a late Pix payment.
RSpec.describe 'Invoice lifecycle operations' do
  let(:user) { User.create!(email: 'inv@agencios.app', password: 'secret123', name: 'Inv') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:invoice) do
    workspace.invoices.create!(client: client, status: :draft, amount_cents: 10_000, due_date: 10.days.from_now)
  end

  before { Current.workspace = workspace }
  after { Current.reset }

  def build_charge(status: 'pending')
    invoice.charges.create!(workspace: workspace, method: :pix, status: status, mp_payment_id: "mp-#{status}-1")
  end

  describe Operations::Invoices::Send do
    it 'opens a draft' do
      described_class.call(invoice: invoice)
      expect(invoice.reload).to be_status_open
    end

    it 'refuses to reopen a canceled invoice' do
      invoice.update!(status: :canceled)
      expect { described_class.call(invoice: invoice) }.to raise_error(Operations::Errors::Invalid)
    end

    it 'refuses to reopen a paid invoice' do
      invoice.update!(status: :paid)
      expect { described_class.call(invoice: invoice) }.to raise_error(Operations::Errors::Invalid)
    end
  end

  describe Operations::Invoices::Cancel do
    it 'cancels the invoice and voids its pending charges (the sweep stops re-checking them)' do
      invoice.update!(status: :open)
      pending = build_charge(status: 'pending')

      described_class.call(invoice: invoice)

      expect(invoice.reload).to be_status_canceled
      expect(pending.reload.status).to eq('cancelled')
    end

    it 'refuses to cancel a paid invoice' do
      invoice.update!(status: :paid)
      expect { described_class.call(invoice: invoice) }.to raise_error(Operations::Errors::Invalid)
    end
  end

  describe Operations::Invoices::Update do
    it 'never edits status and locks the amount once a charge exists' do
      invoice.update!(status: :open)
      build_charge

      expect do
        described_class.call(invoice: invoice, attributes: { amount_cents: 99_999 })
      end.to raise_error(Operations::Errors::Invalid, /valor não pode mudar/)
      # Description stays editable even with a charge out.
      described_class.call(invoice: invoice, attributes: { description: 'Ajuste de texto' })
      expect(invoice.reload.description).to eq('Ajuste de texto')
    end

    it 'refuses edits on paid/canceled invoices' do
      invoice.update!(status: :paid)
      expect { described_class.call(invoice: invoice, attributes: { description: 'x' }) }
        .to raise_error(Operations::Errors::Invalid)
    end
  end

  describe 'Operations::Billing::SyncPaymentStatus with a canceled invoice' do
    it 'records the payment on the charge but NEVER resurrects the invoice as paid' do
      invoice.update!(status: :open)
      charge = build_charge(status: 'pending')
      Operations::Invoices::Cancel.call(invoice: invoice)

      allow(Vendors::MercadoPago::Actions::GetPayment).to receive(:call)
        .and_return({ 'status' => 'approved', 'external_reference' => invoice.external_reference.to_s })
      allow(Operations::Invoices::NotifyPaid).to receive(:call)
      allow(Vendors::Posthog::Actions::Capture).to receive(:call)

      Operations::Billing::SyncPaymentStatus.call(payment_id: charge.mp_payment_id, workspace: workspace)

      expect(charge.reload.status).to eq('approved') # money event is on record
      expect(invoice.reload).to be_status_canceled   # but the invoice stays canceled
      expect(Operations::Invoices::NotifyPaid).not_to have_received(:call)
    end
  end
end
