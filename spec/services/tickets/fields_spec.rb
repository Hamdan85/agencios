# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tickets::Fields do
  it 'no longer allows approval_status on production' do
    out = described_class.sanitize('production', { 'caption' => 'x', 'approval_status' => 'approved' })
    expect(out).to have_key('caption')
    expect(out).not_to have_key('approval_status')
  end
end
