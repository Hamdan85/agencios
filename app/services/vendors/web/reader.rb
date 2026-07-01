# frozen_string_literal: true

require 'open-uri'

module Vendors
  module Web
    # Extracts readable content from a web page to use as carousel source.
    #
    # Returns a Hash `{ title:, text: }` (or nil): `title` is a SHORT subject (the
    # page <title>, trimmed of the site suffix) for the carousel topic, and `text`
    # is the article body capped for the prompt. Plain HTTP fetch first; falls
    # back to the headless browser (Ferrum) for JS-rendered pages. Never raises —
    # a bad link simply yields nil.
    class Reader
      def self.call(...) = new(...).call

      USER_AGENT  = 'Mozilla/5.0 (compatible; AgenciosBot/1.0; +https://agencios.app)'
      MIN_TEXT    = 400 # below this, try the browser
      MAX_TITLE   = 120

      def initialize(url:)
        @url = url.to_s.strip
      end

      def call
        return nil unless @url.match?(%r{\Ahttps?://\S+}i)

        html  = fetch_html
        title = html && title_from(html)
        text  = html ? body_from(html) : ''
        text  = browser_text if text.to_s.length < MIN_TEXT

        text = collapse(text)
        return nil if text.blank?

        { title: clean_title(title).presence || first_sentence(text), text: text }
      end

      private

      def fetch_html
        URI.parse(@url).open('User-Agent' => USER_AGENT, read_timeout: 15, open_timeout: 8, &:read).to_s
      rescue StandardError => e
        Rails.logger.warn("[Vendors::Web::Reader] plain fetch failed for #{@url}: #{e.message}")
        nil
      end

      def browser_text
        Vendors::Render::Html.page_text(url: @url)
      rescue StandardError => e
        Rails.logger.warn("[Vendors::Web::Reader] browser fetch failed for #{@url}: #{e.message}")
        ''
      end

      def title_from(html)
        og = html[/<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']*)["']/i, 1]
        og.presence || html[%r{<title[^>]*>(.*?)</title>}im, 1]
      end

      # Body text with script/style/comments removed first (full_sanitizer keeps
      # their contents otherwise).
      def body_from(html)
        stripped = html
                   .gsub(%r{<script.*?</script>}mi, ' ')
                   .gsub(%r{<style.*?</style>}mi, ' ')
                   .gsub(%r{<noscript.*?</noscript>}mi, ' ')
                   .gsub(/<!--.*?-->/m, ' ')
        ActionView::Base.full_sanitizer.sanitize(stripped).to_s
      end

      # Trim a page title down to the headline subject (drop "… | Site" suffix).
      def clean_title(title)
        return '' if title.blank?

        collapse(title).split(/\s+[|·–—-]\s+/).first.to_s[0, MAX_TITLE]
      end

      def first_sentence(text)
        text.to_s.split(/(?<=[.!?])\s+/).first.to_s[0, MAX_TITLE]
      end

      def collapse(text)
        text.to_s.gsub(/\s+/, ' ').strip
      end
    end
  end
end
