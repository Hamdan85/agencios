# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Approvals::RequestApproval do
  include ActiveJob::TestHelper

  before { ActiveJob::Base.queue_adapter = :test }

  let(:ws) { Workspace.create!(name: 'Agência X', slug: "ws-#{SecureRandom.hex(4)}") }
  let(:client) { Client.create!(workspace: ws, name: 'Cliente', email: 'cliente@ex.co') }
  let(:project) { Project.create!(workspace: ws, client: client, name: 'P', status: :active) }
  let(:ticket) { Ticket.create!(workspace: ws, project: project, status: :production) }
  let(:user) { User.create!(email: 'm@ag.co', password: 'password123', name: 'M') }

  it 'mints a token, stamps requested_at, emails the client, and writes a note' do
    Current.workspace = ws
    ActionMailer::Base.deliveries.clear

    # Block form drains the enqueued mail-delivery job.
    perform_enqueued_jobs do
      described_class.call(ticket: ticket, sent_by: user)
    end

    expect(client.reload.approval_token).to be_present # per-client portal token
    expect(ticket.reload.approval_requested_at).to be_present
    expect(ticket.notes.count).to eq(1)

    expect(ActionMailer::Base.deliveries.size).to eq(1)
    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq(['cliente@ex.co'])
    # Decode the multipart body (quoted-printable soft-wraps the long link).
    decoded = "#{mail.html_part&.body&.decoded} #{mail.text_part&.body&.decoded}"
    expect(decoded).to include("/portal/#{client.reload.approval_token}") # deep-links into the client central
  end

  it 'sends no email and records an honest note when the client has no e-mail' do
    Current.workspace = ws
    client.update!(email: nil)
    ActionMailer::Base.deliveries.clear

    perform_enqueued_jobs do
      described_class.call(ticket: ticket, sent_by: user)
    end

    expect(ActionMailer::Base.deliveries).to be_empty
    expect(ticket.reload.notes.last.display_body).to include('sem e-mail')
  end
end
