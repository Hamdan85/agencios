# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Ai::LogUsage, type: :model do
  let(:workspace) { Workspace.create!(name: 'W', slug: "w-#{SecureRandom.hex(4)}") }

  # Cartesia (voice/TTS) is billed 1 credit per character; the smallest plan
  # (Pro, $5 / 100K credits) sets the conservative rate ≈ $50 / 1M chars.
  describe 'Cartesia voice synthesis cost' do
    it 'prices Cartesia by character (~$50 / 1M chars = 0.005¢/char)' do
      expect(AiUsageLog.unit_cost_cents(provider: 'cartesia', units: 1000)).to eq(5.0)
    end

    it 'logs a Cartesia synthesis into the unified cost ledger' do
      log = described_class.call(
        provider: AiUsageLog::PROVIDER_CARTESIA, operation: 'synthesize_voice',
        units: 200, unit_kind: AiUsageLog::UNIT_CHARACTER, workspace: workspace
      )

      expect(log).to be_persisted
      expect(log.provider).to eq('cartesia')
      expect(log.unit_kind).to eq('character')
      expect(log.units).to eq(200)
      expect(log.cost_cents).to eq(1.0) # 200 × 0.005¢
    end
  end
end
