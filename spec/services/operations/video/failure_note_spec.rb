# frozen_string_literal: true

require 'rails_helper'

# The friendly, actionable PT-BR explanation shown in the chat when a render is
# blocked by the video model's filters.
RSpec.describe Operations::Video::FailureNote do
  it 'explains a copyright block and suggests changing the concept' do
    note = described_class.for(reason: 'The output video may be related to copyright restrictions.', position: 0)
    expect(note).to include('cena 1', 'direitos autorais')
    expect(note).to match(/pessoas reais|mascote|produto/)
  end

  it 'explains an audio-safety block and offers to reword or mute' do
    note = described_class.for(reason: 'output audio may contain sensitive information', position: 1)
    expect(note).to include('cena 2', 'áudio')
    expect(note).to match(/reescrever|sem voz/)
  end

  it 'falls back to a generic, helpful message for an unknown reason' do
    note = described_class.for(reason: 'weird internal error 500', position: 0)
    expect(note).to include('cena 1')
    expect(note).to match(/tentar de novo|mudar a ideia/)
  end
end
