# frozen_string_literal: true

require 'rails_helper'

# Hex → natural color name, so brand colors reach the video model as words to
# grade toward instead of codes it stamps on the frame.
RSpec.describe Operations::Video::ColorName do
  it 'names common brand hues naturally' do
    expect(described_class.call('#035e09')).to eq('deep green')  # Advos green
    expect(described_class.call('#F59E0B')).to eq('orange')      # Advos amber-orange
    expect(described_class.call('#7C3AED')).to eq('indigo')
    expect(described_class.call('#111111')).to eq('near-black')
    expect(described_class.call('#FFFFFF')).to eq('off-white')
    expect(described_class.call('#EC4899')).to eq('pink')
  end

  it 'accepts 3-digit hex and a missing leading #' do
    expect(described_class.call('0a0')).to eq('dark green')
    expect(described_class.call('F59E0B')).to eq('orange')
  end

  it 'returns nil for blank or unparseable input' do
    expect(described_class.call(nil)).to be_nil
    expect(described_class.call('')).to be_nil
    expect(described_class.call('not-a-color')).to be_nil
  end
end
