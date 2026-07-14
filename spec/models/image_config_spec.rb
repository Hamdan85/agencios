# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ImageConfig do
  describe '.instance' do
    it 'returns the row when one exists, without writing when none does' do
      expect(described_class.instance).not_to be_persisted
      row = described_class.create!(default_model: 'google/gemini-2.5-flash-image')
      expect(described_class.instance).to eq(row)
    end
  end

  describe '#model' do
    it 'returns the trimmed slug, or nil when blank (client falls back)' do
      expect(described_class.new(default_model: '  x/y-image ').model).to eq('x/y-image')
      expect(described_class.new(default_model: '   ').model).to be_nil
      expect(described_class.new.model).to be_nil
    end
  end
end
