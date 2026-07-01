# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Client, type: :model do
  describe '.sanitize_positioning' do
    it 'keeps known keys, trims strings, and drops blanks/unknowns' do
      result = described_class.sanitize_positioning(
        'one_liner' => '  faz x  ',
        'statement' => '',
        'bogus_key' => 'drop me',
        'content_pillars' => ['dicas', '', '  bastidores ']
      )

      expect(result).to eq('one_liner' => 'faz x', 'content_pillars' => %w[dicas bastidores])
      expect(result).not_to have_key('bogus_key')
      expect(result).not_to have_key('statement')
    end

    it 'returns an empty hash for blank input' do
      expect(described_class.sanitize_positioning(nil)).to eq({})
      expect(described_class.sanitize_positioning({})).to eq({})
    end
  end

  describe '#positioning?' do
    it 'is true only when at least one field is filled' do
      expect(described_class.new(positioning: {}).positioning?).to be(false)
      expect(described_class.new(positioning: { 'one_liner' => '' }).positioning?).to be(false)
      expect(described_class.new(positioning: { 'one_liner' => 'faz x' }).positioning?).to be(true)
    end
  end
end
