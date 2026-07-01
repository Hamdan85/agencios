# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiConfig do
  describe '#model_for' do
    it 'prefers a per-operation override, else the default model' do
      cfg = described_class.new(default_model: 'anthropic/claude-sonnet-4.5',
                                operation_models: { 'summarize_ticket' => 'google/gemini-2.5-flash' })
      expect(cfg.model_for('summarize_ticket')).to eq('google/gemini-2.5-flash')
      expect(cfg.model_for('fill_fields')).to eq('anthropic/claude-sonnet-4.5')
    end
  end

  describe 'per-operation fields (ActiveAdmin editing)' do
    it 'reads/writes one operation slug via op_model_<operation>' do
      cfg = described_class.new
      cfg.op_model_summarize_ticket = 'google/gemini-2.5-flash'
      expect(cfg.operation_models).to eq('summarize_ticket' => 'google/gemini-2.5-flash')
      expect(cfg.op_model_summarize_ticket).to eq('google/gemini-2.5-flash')
    end

    it 'clearing a field removes the override (blank → back to the default)' do
      cfg = described_class.new(operation_models: { 'fill_fields' => 'openai/gpt-5-mini' })
      cfg.op_model_fill_fields = '  '
      expect(cfg.operation_models).to eq({})
    end
  end

  describe 'the setter always stores a clean map' do
    it 'drops unknown operations and blank/whitespace slugs' do
      cfg = described_class.new(operation_models: { 'bogus_op' => 'x/y', 'fill_fields' => '  ',
                                                    'summarize_ticket' => '  openai/gpt-5-mini ' })
      expect(cfg.operation_models).to eq('summarize_ticket' => 'openai/gpt-5-mini')
      expect(cfg).to be_valid
    end
  end

  describe 'validations' do
    it 'rejects an unknown provider' do
      cfg = described_class.new(provider: 'gemini')
      expect(cfg).not_to be_valid
      expect(cfg.errors[:provider]).to be_present
    end
  end

  describe 'Vendors::Ai routing reads AiConfig (no deploy)' do
    after { described_class.delete_all }

    it 'routes the operation to the admin-configured model' do
      described_class.create!(provider: 'openrouter', default_model: 'anthropic/claude-sonnet-4.5',
                              operation_models: { 'summarize_ticket' => 'openai/gpt-5-mini' })

      expect(Vendors::Ai.provider).to eq('openrouter')
      expect(Vendors::Ai.model_for('summarize_ticket')).to eq('openai/gpt-5-mini')
      expect(Vendors::Ai.model_for('fill_fields')).to eq('anthropic/claude-sonnet-4.5') # default
      expect(Vendors::Ai.client).to be_a(Vendors::OpenRouter::Client)
    end
  end
end
