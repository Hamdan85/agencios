# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Creatives::Create do
  let(:ws) { Workspace.create!(name: 'WS', slug: "ws-#{SecureRandom.hex(4)}") }
  let(:client) { Client.create!(workspace: ws, name: 'C') }
  let(:project) { Project.create!(workspace: ws, client: client, name: 'P', status: :active) }
  let(:ticket) { Ticket.create!(workspace: ws, project: project, status: :production) }

  before { Current.workspace = ws }
  after { Current.reset }

  it 'names an unnamed creative after its type label' do
    creative = described_class.call(ticket: ticket, creative_type: 'feed_image', source: :generated)
    expect(creative.name).to eq('Imagem de feed') # Creatives.spec_for label
  end

  it 'honors an explicit name' do
    creative = described_class.call(ticket: ticket, creative_type: 'feed_image', source: :generated, name: 'Antes e depois')
    expect(creative.name).to eq('Antes e depois')
  end
end
