# frozen_string_literal: true

# One scene of a generated video — an independently-rendered clip. Editing a
# scene re-renders only that scene (reusing its seed); the video Creative is the
# ffmpeg concat of its ready scenes. This is what makes "small edits without
# redoing the whole video" possible.
#
# render_state:
#   fresh     — created, not yet rendered
#   rendering — an OpenRouter job is in flight
#   ready     — clip attached, part of the composed video
#   failed    — the render failed
#   stale     — inputs edited; needs a re-render before the next compose
class VideoScene < ApplicationRecord
  belongs_to :workspace
  belongs_to :creative
  has_one_attached :clip
  # The scene's final frame, extracted after render. Seeds the NEXT scene's first
  # frame so consecutive scenes flow without a jump-cut (visual continuity).
  has_one_attached :last_frame
  # The scene's spoken line synthesized in the video's FIXED voice (Cartesia).
  # Fed to the render as an audio reference (lip-sync) and/or dubbed in post, so
  # the voice is identical across every scene. Cached via metadata['voice_fingerprint'].
  has_one_attached :voice_clip

  enum :render_state, { fresh: 0, rendering: 1, ready: 2, failed: 3, stale: 4 }, prefix: :state

  scope :ordered, -> { order(:position) }

  validates :position, presence: true

  def reference_urls = Array(reference_image_urls)

  # Each reference paired with the ROLE captured at plan time and a STABLE
  # identifier (img_character_v1, vid_camera_ref_v1, …) — the same id the render
  # manifest lists and scene prompts cite (Operations::Video::References). Roles
  # are persisted so the manifest never re-derives them by URL equality (which
  # breaks when a brand asset or the app host changes between plan and render).
  # Preserves the STORED order (it is the submitted input order); falls back to
  # a mode-based role guess for scenes created before roles were persisted.
  def labeled_references
    roles = Array(metadata['reference_roles'])
    descriptions = Array(metadata['reference_descriptions'])
    entries = reference_urls.each_with_index.map do |url, i|
      role = roles[i].presence || default_reference_role(i)
      { url: url, role: role, kind: Operations::Video::References.kind_for(url),
        description: descriptions[i].to_s.strip.presence }
    end
    Operations::Video::References.number(entries)
  end

  # A scene the compose step can use: rendered and with an attached clip.
  def composable? = state_ready? && clip.attached?

  # Publicly-fetchable URL of the extracted last frame (for OpenRouter first-frame
  # conditioning), or nil when not yet extracted.
  def last_frame_url
    return nil unless last_frame.attached?

    Rails.application.routes.url_helpers.rails_blob_url(last_frame, host: SystemConfig.app_host)
  rescue StandardError
    nil
  end

  # Publicly-fetchable URL of the synthesized voice clip (for the render's audio
  # reference), or nil when not synthesized.
  def voice_clip_url
    return nil unless voice_clip.attached?

    Rails.application.routes.url_helpers.rails_blob_url(voice_clip, host: SystemConfig.app_host)
  rescue StandardError
    nil
  end

  private

  # Legacy scenes (no persisted roles): avatar mode carries the avatar first then
  # any attached reference images; product mode carries product photos then the
  # logo last.
  def default_reference_role(index)
    return index.zero? ? 'avatar' : 'reference' if mode == 'avatar'

    index == reference_urls.size - 1 ? 'logo' : 'product'
  end
end
