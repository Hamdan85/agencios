# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VideoConfig do
  describe '#model_for' do
    it 'prefers a per-mode override, else the default model, else the coded seed' do
      cfg = described_class.new(default_model: 'google/veo-3.1-fast',
                                mode_models: { 'product' => 'bytedance/seedance-2.0' })
      expect(cfg.model_for('product')).to eq('bytedance/seedance-2.0')
      expect(cfg.model_for('avatar')).to eq('google/veo-3.1-fast')
    end

    it 'falls back to the coded per-mode seed when nothing is configured' do
      cfg = described_class.new
      expect(cfg.model_for('avatar')).to eq(described_class::DEFAULT_MODE_MODELS['avatar'])
      expect(cfg.model_for('product')).to eq(described_class::DEFAULT_MODE_MODELS['product'])
    end
  end

  describe 'per-mode fields (ActiveAdmin editing)' do
    it 'reads/writes one mode slug via model_<mode>' do
      cfg = described_class.new
      cfg.model_product = 'bytedance/seedance-2.0'
      expect(cfg.mode_models).to eq('product' => 'bytedance/seedance-2.0')
      expect(cfg.model_product).to eq('bytedance/seedance-2.0')
    end

    it 'clearing a field removes the override' do
      cfg = described_class.new(mode_models: { 'avatar' => 'google/veo-3.1-fast' })
      cfg.model_avatar = '  '
      expect(cfg.mode_models).to eq({})
    end
  end

  describe 'the setter always stores a clean map' do
    it 'drops unknown modes and blank/whitespace slugs' do
      cfg = described_class.new(mode_models: { 'bogus' => 'x/y', 'avatar' => '  ',
                                               'product' => '  bytedance/seedance-2.0 ' })
      expect(cfg.mode_models).to eq('product' => 'bytedance/seedance-2.0')
    end

    it 'cleans the draft map the same way' do
      cfg = described_class.new(draft_models: { 'bogus' => 'x/y', 'avatar' => ' a/b ' })
      expect(cfg.draft_models).to eq('avatar' => 'a/b')
    end
  end

  describe '#model_for with quality tiers' do
    it 'resolves draft from the draft map, falling back to the coded draft seed then the final chain' do
      cfg = described_class.new(mode_models: { 'avatar' => 'final/model' },
                                draft_models: { 'avatar' => 'draft/model' })
      expect(cfg.model_for('avatar', quality: 'draft')).to eq('draft/model')
      expect(cfg.model_for('avatar')).to eq('final/model')

      bare = described_class.new
      expect(bare.model_for('avatar', quality: 'draft')).to eq(described_class::DEFAULT_DRAFT_MODELS['avatar'])
      expect(bare.model_for('avatar')).to eq(described_class::DEFAULT_MODE_MODELS['avatar'])
    end
  end

  describe 'music catalog' do
    it 'stores only known moods with a non-blank url, trimmed' do
      cfg = described_class.new(music_tracks: {
                                  'bogus' => { 'url' => 'x' },
                                  'upbeat' => { 'url' => ' https://x/a.mp3 ', 'title' => ' Track A ' },
                                  'calm' => { 'title' => 'no url' }
                                })
      expect(cfg.music_tracks.keys).to eq(['upbeat'])
      expect(cfg.music_tracks['upbeat']).to include('url' => 'https://x/a.mp3', 'title' => 'Track A')
    end

    it 'resolves a track for a mood, or any configured track as a fallback, else nil' do
      cfg = described_class.new(music_tracks: { 'calm' => { 'url' => 'https://x/calm.mp3', 'title' => 'Calm' } })
      expect(cfg.music_track_for('calm')).to include('url' => 'https://x/calm.mp3')
      # A mood with no track still gets music (any configured track).
      expect(cfg.music_track_for('epic')).to include('url' => 'https://x/calm.mp3')
      expect(described_class.new.music_track_for('calm')).to be_nil
    end

    it 'edits one mood url/title via the admin accessors' do
      cfg = described_class.new
      cfg.music_url_upbeat = 'https://x/u.mp3'
      cfg.music_title_upbeat = 'Upbeat One'
      expect(cfg.music_track_for('upbeat')).to include('url' => 'https://x/u.mp3', 'title' => 'Upbeat One')
    end
  end

  describe 'validations' do
    it 'rejects an unknown provider' do
      expect(described_class.new(provider: 'runwayml')).not_to be_valid
    end

    it 'caps the max duration' do
      expect(described_class.new(max_duration_seconds: 5)).to be_valid
      expect(described_class.new(max_duration_seconds: 0)).not_to be_valid
      expect(described_class.new(max_duration_seconds: 999)).not_to be_valid
    end
  end
end
