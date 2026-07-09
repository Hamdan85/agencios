# frozen_string_literal: true

require 'rails_helper'

# The GO-mode auto-send hook: a finalized report e-mails itself to the client
# only when the campaign ran in autopilot (GO) mode.
RSpec.describe Operations::Reports::GenerateProjectReport, '#auto_send_to_client' do
  before do
    ActiveJob::Base.queue_adapter = :test
    allow(AiAdapter).to receive(:complete).and_return('{}') # numbers-only, AI stub
  end

  let(:owner) { User.create!(email: "o-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'O') }
  let(:ws) { Operations::Workspaces::SetupForUser.call(user: owner, name: 'Studio') }
  let(:client) { ws.clients.create!(name: 'ACME', email: 'client@acme.co') }
  let(:project) { ws.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:report) { project.reports.create!(workspace: ws, status: :generating) }

  before { Current.workspace = ws }
  after { Current.reset }

  it 'auto-sends to the client when the campaign ran in GO mode' do
    ticket = Ticket.create!(workspace: ws, project: project, status: :production, channels: ['instagram'])
    AutopilotRun.create!(workspace: ws, ticket: ticket, scope: 'ticket', state: 'completed', user: owner)

    expect(Operations::Reports::SendToClient).to receive(:call).with(report: report)
    described_class.call(report: report)
    expect(report.reload.status).to eq('ready')
  end

  it 'does not auto-send for a manually-run campaign' do
    expect(Operations::Reports::SendToClient).not_to receive(:call)
    described_class.call(report: report)
    expect(report.reload.status).to eq('ready')
  end
end
