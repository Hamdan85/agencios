# frozen_string_literal: true

# Polls ONE video scene's OpenRouter job to completion. On success it downloads
# the clip, attaches it to the scene, and marks it ready — then, if every scene
# of the creative is ready, triggers the compose. A scene failure fails the whole
# generation (a partial video is not shippable). Mirrors PollVideoGenerationJob's
# backoff shape.
require 'open-uri'

class PollVideoSceneJob < ApplicationJob
  queue_as :media

  MAX_ATTEMPTS = 40
  BACKOFF_STEP = 15.seconds

  def perform(scene_id, attempt = 1)
    scene = VideoScene.find_by(id: scene_id)
    return unless scene
    # An already-finalized scene still re-drives the chain: if this job errored
    # AFTER marking the scene ready (e.g. the next scene's submit failed), the
    # Sidekiq retry lands here — advancing again instead of stranding the video.
    return advance_or_compose(scene) if scene.state_ready?
    return if scene.state_failed?
    # Edited while its render was in flight (chat/edit supersede): the old job is
    # void — discard it and render the NEW prompt now (or leave it queued for the
    # chain when an earlier scene isn't ready yet).
    return supersede(scene) if scene.state_stale?
    return if scene.external_id.blank?

    status = Vendors::OpenRouter::Actions::GetVideoStatus.call(job_id: scene.external_id)

    if status[:completed] && status[:video_url].present?
      finalize_scene(scene, status)
    elsif status[:failed]
      fail_scene(scene, status[:failure_message])
    elsif attempt < MAX_ATTEMPTS
      self.class.set(wait: BACKOFF_STEP * [attempt, 8].min).perform_later(scene_id, attempt + 1)
    else
      fail_scene(scene, "Render timed out after #{MAX_ATTEMPTS} polls")
    end
  end

  private

  # The scene was edited mid-flight: ignore the outdated render and submit the
  # new prompt — unless an earlier scene isn't ready yet (the sequential chain
  # will reach it in order, seeded by its predecessor's last frame).
  def supersede(scene)
    pending_before = scene.creative.video_scenes.where('position < ?', scene.position)
                          .where.not(render_state: :ready).exists?
    Operations::Video::RenderScene.call(scene: scene) unless pending_before
  end

  def finalize_scene(scene, status)
    io = Vendors::OpenRouter::Actions::DownloadVideo.call(url: status[:video_url])
    scene.clip.attach(io: io, filename: "scene-#{scene.id}.mp4", content_type: 'video/mp4')
    scene.update!(
      render_state: :ready,
      duration_seconds: status[:duration].presence || scene.duration_seconds,
      cost_cents: status[:cost_cents].present? ? status[:cost_cents].round : scene.cost_cents,
      # 'restyle' is consumed on success: the new look is now the scene's CURRENT
      # look, so any later re-render (incl. the quality upgrade) keeps it via the
      # own-frame seed instead of breaking away from the approved footage.
      metadata: scene.metadata.merge('thumbnail_url' => status[:thumbnail_url]).except('restyle').compact
    )
    extract_last_frame(scene)
    broadcast_progress(scene)
    advance_or_compose(scene)
  ensure
    io&.close if defined?(io) && io.respond_to?(:close)
  end

  # Per-scene progress on the generations channel: the studio/ticket cards
  # invalidate on any event, so the first ready scene surfaces as the card's
  # early preview instead of an opaque spinner until the final compose.
  def broadcast_progress(scene)
    generation = scene.creative.generation
    return unless generation

    ActionCable.server.broadcast(
      "generations_#{generation.workspace_id}",
      { event: 'generation_progress', id: generation.id, kind: 'video',
        status: 'processing', scene_position: scene.position }
    )
  rescue StandardError
    nil
  end

  # Grab the scene's final frame and store it, so the NEXT scene can start from it
  # (visual continuity). Best-effort: a failed extraction just skips conditioning.
  def extract_last_frame(scene)
    scene.clip.open do |clip_file|
      png = "#{clip_file.path}.last.png"
      Vendors::Ffmpeg::LastFrame.call(input_path: clip_file.path, output_path: png)
      scene.last_frame.attach(io: File.open(png), filename: "scene-#{scene.id}-last.png", content_type: 'image/png')
      File.delete(png) if File.exist?(png)
    end
  rescue StandardError => e
    Rails.logger.warn("[PollVideoSceneJob] last-frame extract failed for scene #{scene.id}: #{e.message}")
  end

  # Continue the sequential chain: render the next scene awaiting a render —
  # never-rendered (`fresh`) or queued for re-render (`stale`); RenderScene
  # seeds it with its predecessor's last frame (inlined as pixels, so the
  # continuity conditioning always reaches the engine). Compose once every
  # scene is ready.
  def advance_or_compose(scene)
    creative = scene.creative
    nxt = creative.video_scenes.where(render_state: %i[fresh stale])
                  .where('position > ?', scene.position).order(:position).first
    if nxt
      Operations::Video::RenderScene.call(scene: nxt)
    else
      maybe_compose(creative)
    end
  end

  # Every scene ready → compose the final video (once).
  def maybe_compose(creative)
    creative.reload
    return unless creative.video_scenes.any?
    return unless creative.video_scenes.all?(&:composable?)

    Operations::Video::Compose.call(creative: creative)
  end

  def fail_scene(scene, reason)
    # failure_count survives retries: it tells the chat agent the CONCEPT is
    # being blocked (safety/copyright filter), not just this wording.
    scene.update!(render_state: :failed,
                  metadata: scene.metadata.merge(
                    'failure' => reason.to_s,
                    'failure_count' => scene.metadata['failure_count'].to_i + 1
                  ))
    explain_failure_in_chat(scene, reason)
    generation = scene.creative.generation
    return unless generation

    Operations::Creatives::FailGeneration.call(generation: generation, reason: reason.to_s.presence)
    return unless scene.creative.ticket

    Broadcaster.ticket(scene.creative.ticket, 'creative_failed', creative_id: scene.creative.id)
  end

  # Post a friendly, actionable explanation of the failure into the editor chat,
  # so the user understands WHY the render was blocked (copyright/audio/safety)
  # and what to do — instead of a silent red tile.
  def explain_failure_in_chat(scene, reason)
    note = Operations::Video::FailureNote.for(reason: reason, position: scene.position)
    creative = scene.creative
    creative.push_chat_message(role: :assistant, content: note, kind: 'alert')
    creative.save!
    generation = creative.generation
    return unless generation

    ActionCable.server.broadcast("generations_#{generation.workspace_id}",
                                 { event: 'generation_progress', id: generation.id,
                                   kind: 'video', status: 'failed', chat: true })
  rescue StandardError => e
    Rails.logger.warn("[PollVideoSceneJob] failed to post failure note: #{e.message}")
  end
end
