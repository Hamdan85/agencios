# frozen_string_literal: true

require 'rails_helper'

# The client-approval chip (card/row/detail) is STAGE-AWARE and only flags a
# BLOCKED ticket: awaiting the client in Aprovação, or reworking their feedback
# in Produção. A resolved approval shows no chip — the ticket's column already
# says it moved on. A ticket published without a full sign-off must not keep
# saying "aguardando cliente" forever.
RSpec.describe 'Ticket approval chip state' do
  let(:ws) { Workspace.create!(name: 'WS', slug: "ws-#{SecureRandom.hex(4)}") }
  let(:client) { Client.create!(workspace: ws, name: 'C') }
  let(:project) { Project.create!(workspace: ws, client: client, name: 'P', status: :active) }
  let(:ticket) do
    Ticket.create!(workspace: ws, project: project, status: :approval,
                   approval_requested_at: Time.current)
  end

  before { Current.workspace = ws }
  after { Current.reset }

  def chip = TicketCardSerializer.new(ticket).as_json[:approval][:state]

  def creative!(approval_state)
    Creative.create!(workspace: ws, ticket: ticket, creative_type: 'carousel',
                     status: :ready, approval_state: approval_state)
  end

  it 'is nil when the client was never asked' do
    ticket.update!(approval_requested_at: nil)
    creative!('pending')
    expect(chip).to be_nil
  end

  it 'is pending only while the ticket sits in Aprovação' do
    creative!('pending')
    expect(chip).to eq('pending')
  end

  it 'is changes_requested while the rework sits in Produção' do
    creative!('changes_requested')
    ticket.update!(status: :production)
    expect(chip).to eq('changes_requested')
  end

  it 'shows nothing once the ticket moved past approval without a full sign-off' do
    creative!('pending')
    ticket.update!(status: :published)
    expect(chip).to be_nil
  end

  it 'shows nothing when fully approved — the column already implies it' do
    creative!('approved')
    expect(chip).to be_nil
    ticket.update!(status: :scheduled)
    expect(chip).to be_nil
  end
end
