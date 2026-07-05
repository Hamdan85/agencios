# frozen_string_literal: true

require 'rails_helper'

# The typed media-reference system: stable identifiers (img_character_v1,
# vid_camera_ref_v1), role contracts, priority ordering and versioning — the
# mapping the code stores, the manifest lists and the prompts cite.
RSpec.describe Operations::Video::References do
  describe '.identifier' do
    it 'follows the kind_role_version pattern, with _ref for video guides' do
      expect(described_class.identifier(role: 'character', kind: 'img', version: 1)).to eq('img_character_v1')
      expect(described_class.identifier(role: 'style', kind: 'img', version: 2)).to eq('img_style_v2')
      expect(described_class.identifier(role: 'camera', kind: 'vid', version: 1)).to eq('vid_camera_ref_v1')
      expect(described_class.identifier(role: 'motion', kind: 'vid', version: 2)).to eq('vid_motion_ref_v2')
    end
  end

  describe '.kind_for' do
    it 'detects video by extension, defaults to image' do
      expect(described_class.kind_for('https://cdn/x/clip.mp4')).to eq('vid')
      expect(described_class.kind_for('https://cdn/x/clip.MOV')).to eq('vid')
      expect(described_class.kind_for('https://cdn/x/photo.jpg')).to eq('img')
      expect(described_class.kind_for('https://cdn/x/no-extension')).to eq('img')
      expect(described_class.kind_for('not a url')).to eq('img')
    end
  end

  describe '.build' do
    it 'types, priority-sorts (subject first, logo last) and versions the entries' do
      entries = described_class.build([
                                        { url: 'https://x/logo.png', role: 'logo' },
                                        { url: 'https://x/style.png', role: 'style' },
                                        { url: 'https://x/face.jpg', role: 'character' },
                                        { url: 'https://x/cam.mp4', role: 'camera' }
                                      ])

      expect(entries.map { |e| e[:id] }).to eq(
        %w[img_character_v1 img_style_v1 vid_camera_ref_v1 img_logo_v1]
      )
      expect(entries.map { |e| e[:kind] }).to eq(%w[img img vid img])
    end

    it 'versions repeated roles in order and drops blank urls / unknown roles to reference' do
      entries = described_class.build([
                                        { url: 'https://x/a.jpg', role: 'product' },
                                        { url: '', role: 'product' },
                                        { url: 'https://x/b.jpg', role: 'product' },
                                        { url: 'https://x/c.jpg', role: 'bogus' }
                                      ])

      expect(entries.map { |e| e[:id] }).to eq(%w[img_product_v1 img_product_v2 img_reference_v1])
    end
  end

  describe '.number' do
    it 'assigns identifiers WITHOUT re-sorting (stored order is the submitted order)' do
      entries = described_class.number([
                                         { url: 'https://x/l.png', role: 'logo', kind: 'img' },
                                         { url: 'https://x/p.jpg', role: 'product', kind: 'img' }
                                       ])

      expect(entries.map { |e| e[:id] }).to eq(%w[img_logo_v1 img_product_v1])
    end
  end

  describe '.manifest_lines' do
    it 'anchors each identifier to its input position and role contract' do
      lines = described_class.manifest_lines([
                                               { id: 'img_style_v1', url: 'u', role: 'style', kind: 'img' },
                                               { id: 'vid_motion_ref_v1', url: 'v', role: 'motion', kind: 'vid' }
                                             ])

      expect(lines[0]).to start_with('input 1 = img_style_v1: STYLE reference')
      expect(lines[0]).to include('Never copy its subject')
      expect(lines[1]).to start_with('input 2 = vid_motion_ref_v1: MOTION reference (video)')
    end
  end

  describe '.assignable_role' do
    it 'accepts declared roles, refuses system roles and junk' do
      expect(described_class.assignable_role('camera')).to eq('camera')
      expect(described_class.assignable_role('avatar')).to eq('reference') # system asset
      expect(described_class.assignable_role('logo')).to eq('reference')
      expect(described_class.assignable_role(nil)).to eq('reference')
    end
  end
end
