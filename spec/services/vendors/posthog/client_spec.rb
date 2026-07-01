# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Vendors::Posthog::Client do
  after { described_class.reset! }

  describe '.enabled?' do
    it 'is false without a token, even in production' do
      allow(described_class).to receive(:api_key).and_return(nil)
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      expect(described_class.enabled?).to be(false)
    end

    it 'is false with a token in a non-production env unless opted in' do
      allow(described_class).to receive(:api_key).and_return('phc_test')
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('test'))
      expect(described_class.enabled?).to be(false)
    end

    it 'opts a non-production env in via POSTHOG_ENABLED' do
      allow(described_class).to receive(:api_key).and_return('phc_test')
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('test'))
      expect(ENV).to receive(:[]).with('POSTHOG_ENABLED').and_return('true')
      expect(described_class.enabled?).to be(true)
    end
  end

  describe '.instance' do
    it 'is nil (never builds a real client) when disabled' do
      allow(described_class).to receive(:enabled?).and_return(false)
      expect(described_class.instance).to be_nil
    end
  end
end
