# frozen_string_literal: true

require 'open3'

module Vendors
  module Ffmpeg
    # Extract a clip's OPENING frame as a PNG. Used to re-render a scene while
    # KEEPING its current look: the frame conditions the new render so the world,
    # framing and lighting stay put and only the prompted changes land. Local
    # ffmpeg wrapper — no external API. Returns the output path; raises on failure.
    class FirstFrame
      BIN = ENV.fetch('FFMPEG_BIN', 'ffmpeg')

      def self.call(...) = new(...).call

      def initialize(input_path:, output_path:)
        @in  = input_path
        @out = output_path
      end

      def call
        run(%W[-y -i #{@in} -frames:v 1 -update 1 -q:v 2 #{@out}])
        @out
      end

      private

      def run(args)
        _out, err, st = Open3.capture3(BIN, *args)
        raise "ffmpeg first-frame failed (#{st.exitstatus}): #{err.to_s[0, 400]}" unless st.success?
      end
    end
  end
end
