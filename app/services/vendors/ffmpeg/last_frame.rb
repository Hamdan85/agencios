# frozen_string_literal: true

require 'open3'

module Vendors
  module Ffmpeg
    # Extract a clip's FINAL frame as a PNG. Used to seed the next scene's first
    # frame so consecutive scenes flow continuously (no visual jump-cut). Local
    # ffmpeg wrapper — no external API. Returns the output path; raises on failure.
    class LastFrame
      BIN = ENV.fetch('FFMPEG_BIN', 'ffmpeg')

      def self.call(...) = new(...).call

      def initialize(input_path:, output_path:, seek: 0.1)
        @in   = input_path
        @out  = output_path
        @seek = seek
      end

      def call
        # -sseof seeks relative to end-of-file; grab a single frame just before the
        # end. -update 1 lets the single-image muxer overwrite to one file.
        run(%W[-y -sseof -#{@seek} -i #{@in} -update 1 -frames:v 1 -q:v 2 #{@out}])
        @out
      end

      private

      def run(args)
        _out, err, st = Open3.capture3(BIN, *args)
        raise "ffmpeg last-frame failed (#{st.exitstatus}): #{err.to_s[0, 400]}" unless st.success?
      end
    end
  end
end
