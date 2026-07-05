# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VideoConfig do
  describe '#model_for (two engines, mode-independent)' do
    it 'resolves final from default_model and draft from draft_model' do
      cfg = described_class.new(default_model: 'final/model', draft_model: 'draft/model')
      expect(cfg.model_for('avatar')).to eq('final/model')
      expect(cfg.model_for('product')).to eq('final/model')
      expect(cfg.model_for('avatar', quality: 'draft')).to eq('draft/model')
      # The mode never changes the model — same slug regardless of mode.
      expect(cfg.model_for('scene', quality: 'draft')).to eq('draft/model')
    end

    it 'ignores the mode entirely (it is optional)' do
      cfg = described_class.new(default_model: 'final/model', draft_model: 'draft/model')
      expect(cfg.model_for).to eq('final/model')
      expect(cfg.model_for(nil, quality: 'draft')).to eq('draft/model')
    end

    it 'falls back to the coded seeds when nothing is configured' do
      bare = described_class.new
      expect(bare.model_for('avatar')).to eq(described_class::DEFAULT_MODEL)
      expect(bare.model_for('avatar', quality: 'draft')).to eq(described_class::DEFAULT_DRAFT_MODEL)
    end

    it 'draft falls back to the final chain when no draft model is set' do
      cfg = described_class.new(default_model: 'final/model', draft_model: nil)
      # coded draft seed is used first; but with a bespoke final and no draft, the
      # draft seed still applies (draft is independent of final).
      expect(cfg.model_for('avatar', quality: 'draft')).to eq(described_class::DEFAULT_DRAFT_MODEL)
    end
  end

  describe 'clip-length options + snapping' do
    it 'returns the engines\' supported clip lengths (draft ∩ final)' do
      # veo family (draft veo-3.1-fast, final veo-3.1), both [4,6,8].
      cfg = described_class.new(default_model: 'google/veo-3.1', draft_model: 'google/veo-3.1-fast')
      expect(cfg.clip_seconds_for('avatar')).to eq([4, 6, 8])
    end

    it 'falls back to the default set for an unknown/unlisted model' do
      cfg = described_class.new(default_model: 'brand/new-engine', draft_model: 'brand/new-engine')
      expect(cfg.clip_seconds_for).to eq(described_class::DEFAULT_CLIP_SECONDS)
    end

    it 'snaps an arbitrary duration to the nearest supported length (ties round down)' do
      cfg = described_class.new(default_model: 'google/veo-3.1', draft_model: 'google/veo-3.1-fast') # [4, 6, 8]
      expect(cfg.snap_seconds(8, 'avatar')).to eq(8) # already valid
      expect(cfg.snap_seconds(7, 'avatar')).to eq(6) # tie 6/8 → down
      expect(cfg.snap_seconds(5, 'avatar')).to eq(4) # tie 4/6 → down
      expect(cfg.snap_seconds(100, 'avatar')).to eq(8) # clamp to max option
      expect(cfg.snap_seconds(0)).to eq(4)             # blank/zero → shortest, mode optional
    end
  end

  describe 'voice catalog (Cartesia)' do
    it 'parses the admin text (label = voice_id per line) and drops incomplete rows' do
      cfg = described_class.new
      cfg.voice_catalog_text = "Feminina BR = voice_abc\n  Masculina BR = voice_xyz \n\nSó rótulo =\n= só_id"
      expect(cfg.voices).to eq('Feminina BR' => 'voice_abc', 'Masculina BR' => 'voice_xyz')
      expect(cfg.voice_catalog_text).to eq("Feminina BR = voice_abc\nMasculina BR = voice_xyz")
    end

    it 'resolves a label, a raw voice_id, or the default' do
      cfg = described_class.new(voice_catalog: { 'Feminina BR' => 'voice_abc' }, default_voice_id: 'voice_def')
      expect(cfg.resolved_voice_id('Feminina BR')).to eq('voice_abc') # by label
      expect(cfg.resolved_voice_id('voice_abc')).to eq('voice_abc')   # by raw id in catalog
      expect(cfg.resolved_voice_id('inexistente')).to eq('voice_def') # → default
      expect(cfg.resolved_voice_id(nil)).to eq('voice_def')
    end

    it 'is off (nil) when nothing is configured' do
      expect(described_class.new.resolved_voice_id('x')).to be_nil
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
