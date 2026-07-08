# frozen_string_literal: true

require 'open3'
require 'tempfile'

module Vendors
  module Ffmpeg
    # Probe the duration (in seconds, Float) of a media file or an in-memory blob
    # of bytes via ffprobe. Returns 0.0 on any error (never raises) — callers use
    # it to SIZE the audio-driven trim, so a probe failure must degrade to "unknown
    # length" (skip the fit), never blow up a render.
    #
    # Local tool wrapper (like Vendors::Ffmpeg::Concat) — no external API.
    class Duration
      PROBE_BIN = ENV.fetch('FFPROBE_BIN', 'ffprobe')

      def self.call(...) = new(...).call

      # Pass EITHER path: (a file on disk) OR bytes: (raw media bytes, e.g. the
      # Cartesia mp3), plus an optional ext for the temp file.
      def initialize(path: nil, bytes: nil, ext: '.mp3')
        @path  = path
        @bytes = bytes
        @ext   = ext
      end

      def call
        return probe(@path) if @path.present?
        return 0.0 if @bytes.blank?

        Tempfile.create(['ffdur', @ext]) do |f|
          f.binmode
          f.write(@bytes)
          f.flush
          probe(f.path)
        end
      rescue StandardError => e
        Rails.logger.warn("[Ffmpeg::Duration] #{e.class}: #{e.message}")
        0.0
      end

      private

      def probe(path)
        out, _err, st = Open3.capture3(PROBE_BIN, *%W[-v error -show_entries format=duration
                                                      -of csv=p=0 #{path}])
        st.success? ? out.strip.to_f : 0.0
      end
    end
  end
end
