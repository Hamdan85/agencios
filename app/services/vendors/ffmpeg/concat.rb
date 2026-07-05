# frozen_string_literal: true

require 'open3'
require 'shellwords'

module Vendors
  module Ffmpeg
    # Concatenate scene clips into one video. Clips may differ in resolution and
    # some engines emit no audio track, so each input is first normalized to the
    # target WxH (letterboxed), 30fps, with a guaranteed (possibly silent) stereo
    # audio track — then joined with the concat demuxer (stream copy). A single
    # input is just normalized. Returns the output path. Raises on ffmpeg failure.
    #
    # Local tool wrapper (like Vendors::Render::Html) — no external API.
    class Concat
      BIN = ENV.fetch('FFMPEG_BIN', 'ffmpeg')
      PROBE_BIN = ENV.fetch('FFPROBE_BIN', 'ffprobe')

      def self.call(...) = new(...).call

      # music_path: an optional local audio file mixed UNDER the joined audio
      # (looped to the video length) — one continuous soundtrack burned in.
      # music_mix: the orchestrator-controlled parameters
      # { volume:, fade_in:, fade_out:, duck: } (duck lowers the music under the
      # speech via sidechain compression).
      # voice_paths: an optional array PARALLEL to input_paths — a synthesized
      # fixed-voice clip per scene (nil where none). When present the model's own
      # audio is DROPPED (it drifts the voice + adds its own music) and DUBBED:
      # each voice clip is laid at its scene's offset, music ducked under it. This
      # is what makes the voice identical across scenes + guarantees music comes
      # only from `music_path` (the model never contributes audio).
      def initialize(input_paths:, width:, height:, output_path:, mute: false, music_path: nil,
                     music_mix: {}, voice_paths: [])
        @inputs = Array(input_paths)
        @w = width.to_i
        @h = height.to_i
        @out = output_path
        @mute = mute
        @music = music_path
        @mix = (music_mix || {}).transform_keys(&:to_sym)
        @voices = Array(voice_paths)
      end

      def call
        raise ArgumentError, 'no input clips' if @inputs.empty?

        Dir.mktmpdir('hf-concat') do |dir|
          normalized = @inputs.each_with_index.map { |src, i| normalize(src, File.join(dir, "n#{i}.mp4")) }
          joined = File.join(dir, 'joined.mp4')
          if normalized.one?
            FileUtils.cp(normalized.first, joined)
          else
            join(normalized, joined)
          end
          if dub?
            dub_audio(joined, scene_offsets(normalized), @out)
          elsif @music.present?
            mix_music(joined, @out)
          else
            FileUtils.cp(joined, @out)
          end
        end
        @out
      end

      DEFAULT_MIX = { volume: 0.28, fade_in: 1.0, fade_out: 2.0, duck: true }.freeze

      private

      # Dubbing replaces the model audio entirely (fixed voice + post music), so
      # the clips are normalized muted.
      def dub? = @voices.any?(&:present?)
      def mute? = @mute || dub?

      # Cumulative start time (seconds) of each scene in the joined video.
      def scene_offsets(normalized)
        acc = 0.0
        normalized.map { |p| acc.tap { acc += probe_duration(p) } }
      end

      # DUB: the joined video is silent; lay each scene's fixed-voice clip at its
      # offset, then the (looped, faded) music ducked under the combined voice.
      # One continuous consistent voice + one controlled soundtrack; the model
      # contributes no audio at all. Falls back to music-only / silent on error.
      def dub_audio(joined, offsets, out)
        voiced = @voices.each_with_index.filter_map { |vp, i| vp.present? ? [vp, offsets[i].to_f] : nil }
        return @music.present? ? mix_music(joined, out) : FileUtils.cp(joined, out) if voiced.empty?

        dur = probe_duration(joined)
        inputs = %W[-y -i #{joined}]
        voiced.each { |vp, _| inputs += ['-i', vp] }
        inputs += %W[-stream_loop -1 -i #{@music}] if @music.present?

        # Pin the output to the VIDEO length (`-t`): the ducked music sidechain
        # ends with the last voice clip, so `-shortest` would clip the tail.
        run(inputs + %W[-filter_complex #{dub_filter(voiced)} -map 0:v:0 -map [aout]
                        -c:v copy -c:a aac -ar 44100 -t #{dur.round(3)} #{out}])
      rescue StandardError => e
        Rails.logger.warn("[Ffmpeg::Concat] dub failed, falling back: #{e.message}")
        @music.present? ? (mix_music(joined, out) rescue FileUtils.cp(joined, out)) : FileUtils.cp(joined, out) # rubocop:disable Style/RescueModifier
      end

      # filter_complex for the dub: delay each voice to its scene offset, sum the
      # voices into one bus, then (optionally) duck the looped/faded music under
      # that bus. Voice inputs are 1..N; music (when present) is N+1.
      def dub_filter(voiced)
        parts = voiced.each_with_index.map do |(_, off), j|
          "[#{j + 1}:a]adelay=#{(off * 1000).round}|#{(off * 1000).round}[v#{j}]"
        end
        if voiced.size == 1
          parts << '[v0]anull[voice]'
        else
          parts << "#{voiced.each_index.map { |j| "[v#{j}]" }.join}amix=inputs=#{voiced.size}:duration=longest:dropout_transition=0[voice]"
        end

        return "#{parts.join(';')};[voice]anull[aout]" if @music.blank?

        music_idx = voiced.size + 1
        v = num(@mix[:volume], DEFAULT_MIX[:volume])
        fin = num(@mix[:fade_in], DEFAULT_MIX[:fade_in])
        fout = num(@mix[:fade_out], DEFAULT_MIX[:fade_out])
        parts << "[#{music_idx}:a]volume=#{v},afade=t=in:st=0:d=#{fin}[m]"
        if @mix.fetch(:duck, DEFAULT_MIX[:duck])
          parts << '[voice]asplit=2[vmain][vsc]'
          parts << '[m][vsc]sidechaincompress=threshold=0.03:ratio=6:attack=20:release=400[md]'
          parts << '[vmain][md]amix=inputs=2:duration=longest:dropout_transition=0[aout]'
        else
          parts << '[voice][m]amix=inputs=2:duration=longest:dropout_transition=0[aout]'
        end
        parts.join(';')
      end

      # Overlay the (looped) music under the joined video's audio, with the
      # orchestrator's volume + fades, optionally ducking it under the speech;
      # stops at the video's duration (`-shortest`).
      def mix_music(joined, out)
        dur = probe_duration(joined)
        v = num(@mix[:volume], DEFAULT_MIX[:volume])
        fin = num(@mix[:fade_in], DEFAULT_MIX[:fade_in])
        fout = num(@mix[:fade_out], DEFAULT_MIX[:fade_out])
        fout_start = [dur - fout, 0].max.round(2)
        duck = @mix.fetch(:duck, DEFAULT_MIX[:duck])

        music_chain = "[1:a]volume=#{v},afade=t=in:st=0:d=#{fin},afade=t=out:st=#{fout_start}:d=#{fout}[m]"
        filter =
          if duck
            "[0:a]asplit=2[sp1][sp2];#{music_chain};" \
              '[m][sp2]sidechaincompress=threshold=0.03:ratio=6:attack=20:release=400[md];' \
              '[sp1][md]amix=inputs=2:duration=first:dropout_transition=0[aout]'
          else
            "#{music_chain};[0:a][m]amix=inputs=2:duration=first:dropout_transition=0[aout]"
          end

        run(%W[-y -i #{joined} -stream_loop -1 -i #{@music}
               -filter_complex #{filter} -map 0:v:0 -map [aout]
               -c:v copy -c:a aac -ar 44100 -shortest #{out}])
      rescue StandardError => e
        # A music-mix failure must never lose the video — ship it without music.
        Rails.logger.warn("[Ffmpeg::Concat] music mix failed, shipping without music: #{e.message}")
        FileUtils.cp(joined, out)
      end

      def num(value, default)
        return default if value.nil?

        n = value.to_f
        n.negative? ? default : n
      end

      def probe_duration(src)
        out, _err, st = Open3.capture3(PROBE_BIN, *%W[-v error -show_entries format=duration
                                                      -of csv=p=0 #{src}])
        st.success? ? out.strip.to_f : 0.0
      end

      # Scale+pad to target frame, 30fps, and guarantee a stereo audio track so
      # every normalized clip is concat-compatible. The source's REAL audio is
      # preserved when present (models like Veo 3.1 emit native audio/speech); a
      # silent track is injected ONLY when the clip has none.
      def normalize(src, dst)
        vf = "scale=#{@w}:#{@h}:force_original_aspect_ratio=decrease," \
             "pad=#{@w}:#{@h}:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30"
        args =
          if has_audio?(src) && !mute?
            %W[-y -i #{src} -vf #{vf} -map 0:v:0 -map 0:a:0
               -c:v libx264 -pix_fmt yuv420p -c:a aac -ar 44100 #{dst}]
          else
            %W[-y -i #{src} -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100
               -vf #{vf} -map 0:v:0 -map 1:a:0 -shortest
               -c:v libx264 -pix_fmt yuv420p -c:a aac -ar 44100 #{dst}]
          end
        run(args)
        dst
      end

      # True when the clip carries at least one audio stream. Probed so we never
      # clobber real audio with silence (nor concat-fail on a clip that lacks it).
      def has_audio?(src)
        out, _err, st = Open3.capture3(PROBE_BIN, *%W[-v error -select_streams a
                                                      -show_entries stream=index -of csv=p=0 #{src}])
        st.success? && out.strip.present?
      rescue StandardError
        false
      end

      def join(paths, out)
        list = "#{out}.list.txt"
        File.write(list, paths.map { |p| "file '#{p}'" }.join("\n"))
        run(%W[-y -f concat -safe 0 -i #{list} -c copy #{out}])
      end

      def run(args)
        _out, err, st = Open3.capture3(BIN, *args)
        raise "ffmpeg failed (#{st.exitstatus}): #{err.to_s[0, 400]}" unless st.success?
      end
    end
  end
end
