# frozen_string_literal: true

require 'rails_helper'

# The GO "two identical feed_image creatives" bug: creative types were persisted
# and read without de-duplication, so KickGenerations generated one per entry.
RSpec.describe 'Creative types de-duplication' do
  let(:ws) { Workspace.create!(name: 'WS', slug: "ws-#{SecureRandom.hex(4)}") }
  let(:client) { Client.create!(workspace: ws, name: 'C') }
  let(:project) { Project.create!(workspace: ws, client: client, name: 'P', status: :active) }

  before { Current.workspace = ws }
  after { Current.reset }

  it 'Ticket#creative_types_list de-dups (even legacy dirty stored data)' do
    ticket = Ticket.create!(workspace: ws, project: project, status: :scoping,
                            fields: { 'scoping' => { 'creative_types' => %w[feed_image feed_image carousel] } })
    expect(ticket.creative_types_list).to eq(%w[feed_image carousel])
  end

  it 'UpdateFields stores a de-duplicated creative_types column + field' do
    ticket = Ticket.create!(workspace: ws, project: project, status: :scoping)
    Operations::Tickets::UpdateFields.call(
      ticket: ticket, status: 'scoping', values: { 'creative_types' => %w[feed_image feed_image carousel] }
    )
    ticket.reload
    expect(ticket.creative_types).to eq(%w[feed_image carousel])
    expect(ticket.fields_for('scoping')['creative_types']).to eq(%w[feed_image carousel])
  end
end
