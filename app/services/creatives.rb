# frozen_string_literal: true

# Creative-type registry. Maps a creative_type key (the spec key stored on a
# Creative / Ticket) to its spec class under `app/services/creatives/`.
#
# This file defines the `Creatives` MODULE namespace and the registry lookup as
# module functions; the type classes (`Creatives::Reel`, etc.) live in the
# `creatives/` subdirectory (both map to the same `Creatives` constant under
# Zeitwerk, which is why the registry lives here as `module_function`s).
module Creatives
  TYPES = %w[reel feed_image carousel story ugc_video ad thumbnail cover].freeze

  module_function

  def registry
    @registry ||= {
      'reel' => Creatives::Reel,
      'feed_image' => Creatives::FeedImage,
      'carousel' => Creatives::Carousel,
      'story' => Creatives::Story,
      'ugc_video' => Creatives::UgcVideo,
      'ad' => Creatives::Ad,
      'thumbnail' => Creatives::Thumbnail,
      'cover' => Creatives::Cover
    }
  end

  # The spec class for a type key, or nil if unknown.
  def for(type_key)
    registry[type_key.to_s]
  end

  # The structural spec hash for a type key, or nil if unknown.
  def spec_for(type_key)
    self.for(type_key)&.spec
  end

  # The media kinds a MANUAL UPLOAD accepts for a creative type (the top-level of
  # the file content type). Derived from the type's spec `kind`: video types take
  # video, everything else takes images — except a story, which takes either
  # (IG/FB stories can be image or video). The upload guard + the frontend's
  # `accept` both read this so a file can't mismatch the ticket's media type.
  def accepted_upload_media(type_key)
    return %w[image video] if type_key.to_s == 'story'

    spec_for(type_key)&.dig(:kind) == 'video' ? %w[video] : %w[image]
  end

  # Every registered type's spec — used by the studio to render the type picker.
  def all_specs
    registry.values.map(&:spec)
  end
end
