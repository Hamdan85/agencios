# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Video::PromptDialects do
  # A representative spec exercising every slot + contract, so the "nothing gets
  # lost when the dialect changes" requirement is a real regression guard.
  def spec(dialect: :seedance, mode: :t2v, guardrails: ['alcohol', 'minors on camera'])
    Operations::Video::PromptSpec.new(
      cinematography: 'slow push-in, medium close-up',
      narrative: 'A barista pours latte art onto a flat white, warm morning light',
      style_fence: 'Look & feel: grade toward deep green and warm amber.',
      audio: ['Audio boundary: render this clip SILENT — voice and music are added in post.'],
      technical: ['Pacing/trim: this clip is 8s but the scene is TRIMMED to about 6s.'],
      identity: 'Project identity — keep IDENTICAL in every scene: the SAME barista.',
      continuity: 'Continuity: this scene is the NEXT BEAT of an ongoing video.',
      references: ['input 1 = img_product_v1: PRODUCT reference — keep the product faithful.'],
      on_screen_text: 'On-screen text: NONE — never invent lettering.',
      guardrails: guardrails,
      mode: mode, dialect: dialect, aspect_ratio: '9:16'
    )
  end

  describe 'model → dialect mapping' do
    it 'routes each engine slug to its dialect (else the default)' do
      expect(described_class.dialect_for_model('bytedance/seedance-2.0')).to eq(:seedance)
      expect(described_class.dialect_for_model('bytedance/seedance-2.0-fast')).to eq(:seedance)
      expect(described_class.dialect_for_model('google/veo-3.1')).to eq(:veo)
      expect(described_class.dialect_for_model('kwaivgi/kling-v3.0-pro')).to eq(:kling)
      expect(described_class.dialect_for_model('some/unknown-engine')).to eq(:default)
    end
  end

  describe 'Seedance dialect (primary)' do
    subject(:out) { described_class.serialize(spec(dialect: :seedance)) }

    it 'leads with the visual narrative, then the camera as its OWN clause' do
      expect(out).to start_with('A barista pours latte art')
      expect(out).to include('Camera: slow push-in, medium close-up.')
    end

    it 'phrases negatives as an in-prompt avoid clause' do
      expect(out).to include('Avoid (must NOT appear or happen): alcohol; minors on camera.')
    end
  end

  describe 'Veo dialect' do
    subject(:out) { described_class.serialize(spec(dialect: :veo)) }

    it 'leads with the cinematography (camera first)' do
      expect(out).to start_with('slow push-in, medium close-up.')
    end

    it 'phrases negatives POSITIVELY (Veo ignores negation)' do
      expect(out).to include('Keep the scene entirely free of alcohol, minors on camera')
      expect(out).not_to include('must NOT contain', 'Avoid (must NOT')
    end
  end

  describe 'Kling dialect' do
    subject(:out) { described_class.serialize(spec(dialect: :kling)) }

    it 'leads camera-first as scene direction' do
      expect(out).to start_with('Camera: slow push-in, medium close-up.')
    end
  end

  describe 'nothing is lost across dialects (regression guard)' do
    %i[seedance veo kling default].each do |dialect|
      it "keeps every context source + contract for #{dialect}" do
        out = described_class.serialize(spec(dialect: dialect))
        expect(out).to include(
          'A barista pours latte art',                 # narrative
          'slow push-in, medium close-up',             # camera
          'Look & feel: grade toward deep green',      # brand style
          'Audio boundary',                            # audio contract
          'Pacing/trim',                               # technical/trim
          'Project identity',                          # identity
          'Continuity: this scene is the NEXT BEAT',   # continuity
          'input 1 = img_product_v1',                  # reference manifest
          'On-screen text: NONE',                      # lettering contract
          'alcohol'                                     # guardrail (phrasing varies)
        )
      end
    end
  end

  describe 'image-to-video mode' do
    it 'instructs motion + stability only, never re-describing the frame' do
      %i[seedance veo kling].each do |dialect|
        out = described_class.serialize(spec(dialect: dialect, mode: :i2v))
        expect(out.downcase).to include('provided')                     # references the given frame/image
        expect(out.downcase).to match(/motion|change|evolves/)          # motion-focused
        expect(out.downcase).to match(/preserve|stay exactly|as in the image/) # stability
      end
    end

    it 'does NOT add the i2v directive in plain text-to-video' do
      out = described_class.serialize(spec(dialect: :seedance, mode: :t2v))
      expect(out).not_to include('Animate the provided reference frame')
    end
  end
end
