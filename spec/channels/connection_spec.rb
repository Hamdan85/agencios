# frozen_string_literal: true

require 'rails_helper'

# The login-less portal relies on anonymous cable connections being allowed
# (current_user nil). PortalChannel accepting a nil-user connection (see
# portal_channel_spec) proves anonymous connects work; here we prove the member-
# only streams still reject a nil user, so anonymous access was not widened.
RSpec.describe BoardChannel, type: :channel do
  it 'rejects an anonymous subscriber (member-only stream stays closed)' do
    stub_connection(current_user: nil)
    subscribe(workspace_id: 1)
    expect(subscription).to be_rejected
  end
end

RSpec.describe TicketChannel, type: :channel do
  it 'rejects an anonymous subscriber' do
    stub_connection(current_user: nil)
    subscribe(ticket_id: 1)
    expect(subscription).to be_rejected
  end
end
