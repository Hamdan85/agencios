# frozen_string_literal: true

module Operations
  module Video
    # Turns a hex color into a natural-language name ("deep green", "warm amber").
    # Video models are literal: a raw "#035e09" in the prompt gets printed on
    # screen as text. Color intent must reach the model as WORDS it can grade
    # toward, never as a code it can stamp on the frame.
    module ColorName
      module_function

      HUES = [
        [15,  'red'],   [40,  'orange'], [50,  'amber'], [70,  'yellow'],
        [95,  'lime'],  [155, 'green'],  [185, 'teal'],  [200, 'cyan'],
        [250, 'blue'],  [280, 'indigo'], [320, 'purple'], [345, 'pink'], [360, 'red']
      ].freeze

      # nil for a blank/unparseable value.
      def call(hex)
        rgb = parse(hex)
        return nil unless rgb

        h, s, l = hsl(*rgb)
        return achromatic(l) if s < 0.12

        "#{lightness_qualifier(l)}#{hue(h)}".strip
      end

      def parse(hex)
        m = hex.to_s.strip.delete('#')
        m = m.chars.map { |c| c * 2 }.join if m.length == 3
        return nil unless m.length == 6 && m.match?(/\A[0-9a-fA-F]{6}\z/)

        [m[0, 2], m[2, 2], m[4, 2]].map { |p| p.to_i(16) }
      end

      def hsl(r, g, b)
        r /= 255.0
        g /= 255.0
        b /= 255.0
        max = [r, g, b].max
        min = [r, g, b].min
        l = (max + min) / 2
        d = max - min
        return [0.0, 0.0, l] if d.zero?

        s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
        h = case max
            when r then ((g - b) / d) % 6
            when g then ((b - r) / d) + 2
            else        ((r - g) / d) + 4
            end
        [(h * 60) % 360, s, l]
      end

      def hue(h)
        HUES.find { |limit, _| h <= limit }.last
      end

      def lightness_qualifier(l)
        return 'deep ' if l < 0.28
        return 'dark ' if l < 0.42
        return 'bright ' if l > 0.72

        ''
      end

      def achromatic(l)
        return 'near-black' if l < 0.15
        return 'off-white' if l > 0.88
        return 'light grey' if l > 0.6

        l < 0.35 ? 'dark grey' : 'grey'
      end
    end
  end
end
