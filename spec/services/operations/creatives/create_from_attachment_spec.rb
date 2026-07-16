# frozen_string_literal: true

require 'rails_helper'

# A ticket file becomes a ready creative sharing the attachment's blob (no
# re-upload), guarded by the type's accepted media.
RSpec.describe Operations::Creatives::CreateFromAttachment do
  let(:user) { User.create!(email: 'cfa@agencios.app', password: 'secret123', name: 'CF') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:ticket) do
    Operations::Tickets::Create.call(
      workspace: workspace, user: user, params: { project_id: project.id, title: 'T', channels: %w[instagram] }
    )
  end

  before { Current.workspace = workspace }
  after { Current.reset }

  def build_attachment(content_type:, filename:)
    attachment = ticket.attachments.new(workspace: workspace, uploaded_by: user)
    attachment.file.attach(
      io: StringIO.new('fake-bytes'), filename: filename, content_type: content_type
    )
    attachment.save!
    attachment
  end

  it 'creates a READY uploaded creative that shares the attachment blob' do
    attachment = build_attachment(content_type: 'image/png', filename: 'foto.png')

    creative = described_class.call(ticket: ticket, attachment: attachment, creative_type: 'feed_image')

    expect(creative).to be_persisted
    expect(creative).to be_source_uploaded
    expect(creative).to be_status_ready
    expect(creative.ticket).to eq(ticket)
    expect(creative.metadata['attachment_id']).to eq(attachment.id)
    expect(creative.assets.first.blob).to eq(attachment.file.blob)
  end

  it 'refuses media the creative type does not accept (image cannot become a reel)' do
    attachment = build_attachment(content_type: 'image/png', filename: 'foto.png')

    expect { described_class.call(ticket: ticket, attachment: attachment, creative_type: 'reel') }
      .to raise_error(Operations::Errors::Invalid)
    expect(ticket.creatives.count).to eq(0)
  end

  it 'refuses non-media files (a PDF is never a creative)' do
    attachment = build_attachment(content_type: 'application/pdf', filename: 'brief.pdf')

    expect { described_class.call(ticket: ticket, attachment: attachment, creative_type: 'feed_image') }
      .to raise_error(Operations::Errors::Invalid)
  end

  it 'deleting the creative keeps the attachment file intact (shared blob survives)' do
    attachment = build_attachment(content_type: 'image/png', filename: 'foto.png')
    creative = described_class.call(ticket: ticket, attachment: attachment, creative_type: 'feed_image')

    blob = attachment.file.blob
    creative.destroy!

    expect(attachment.reload.file).to be_attached
    expect(ActiveStorage::Blob.exists?(blob.id)).to be(true)
  end
end
