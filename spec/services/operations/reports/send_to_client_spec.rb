# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Reports::SendToClient do
  include ActiveJob::TestHelper

  before do
    ActiveJob::Base.queue_adapter = :test
    # Keep Chromium out of the unit path — the PDF render is exercised separately.
    allow(Vendors::Render::Pdf).to receive(:call).and_return('%PDF-1.4 fake')
  end

  let(:owner) { User.create!(email: "o-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'O') }
  let(:ws) { Operations::Workspaces::SetupForUser.call(user: owner, name: 'Studio') }
  let(:client) { ws.clients.create!(name: 'ACME', email: 'client@acme.co') }
  let(:project) { ws.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:report) { project.reports.create!(workspace: ws, status: :ready, data: { 'kpis' => {} }) }

  before { Current.workspace = ws }
  after { Current.reset }

  it 'renders the PDF, e-mails the client with the attachment, and stamps sent_to_client_at' do
    expect do
      expect(described_class.call(report: report)).to be(true)
    end.to have_enqueued_mail(ReportMailer, :deck)

    expect(report.reload.sent_to_client_at).to be_present
    expect(report.pdf).to be_attached
  end

  it 'no-ops when the report is not ready' do
    report.update!(status: :generating)
    expect(described_class.call(report: report)).to be(false)
    expect { described_class.call(report: report) }.not_to have_enqueued_mail(ReportMailer, :deck)
  end

  it 'no-ops when the client has no e-mail' do
    client.update!(email: nil)
    expect(described_class.call(report: report)).to be(false)
    expect(report.reload.sent_to_client_at).to be_nil
  end
end
