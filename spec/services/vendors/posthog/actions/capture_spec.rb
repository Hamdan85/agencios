# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Vendors::Posthog::Actions::Capture do
  subject { described_class }

  after { Vendors::Posthog::Client.reset! }

  context 'when PostHog is disabled (no client)' do
    before { allow(Vendors::Posthog::Client).to receive(:instance).and_return(nil) }

    it 'no-ops and returns false' do
      expect(subject.call(event: 'sign_up', distinct_id: '7')).to be(false)
    end
  end

  context 'when PostHog is enabled' do
    let(:client) { instance_double(PostHog::Client) }

    before { allow(Vendors::Posthog::Client).to receive(:instance).and_return(client) }

    it 'captures with the user id as distinct_id (matching the SPA identify)' do
      user = instance_double('User', id: 42)
      expect(client).to receive(:capture).with({
                                                  distinct_id: '42',
                                                  event: 'subscription_payment',
                                                  properties: { plan: 'agencia' }
                                                })
      expect(subject.call(user: user, event: 'subscription_payment', properties: { plan: 'agencia' })).to be(true)
    end

    it 'includes and compacts groups when given' do
      expect(client).to receive(:capture).with({
                                                  distinct_id: '1',
                                                  event: 'client_invoice_paid',
                                                  properties: { amount_cents: 9900 },
                                                  groups: { workspace: 5 }
                                                })
      subject.call(distinct_id: '1', event: 'client_invoice_paid',
                   properties: { amount_cents: 9900, currency: nil }, groups: { workspace: 5 })
    end

    it 'skips when there is no distinct id' do
      expect(client).not_to receive(:capture)
      expect(subject.call(event: 'sign_up')).to be(false)
    end

    it 'swallows errors so instrumentation never breaks the caller' do
      allow(client).to receive(:capture).and_raise(StandardError, 'boom')
      expect(subject.call(event: 'x', distinct_id: '1')).to be(false)
    end
  end
end
