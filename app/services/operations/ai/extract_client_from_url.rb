# frozen_string_literal: true

module Operations
  module Ai
    # Reads a brand's landing page / site and extracts a full client DRAFT:
    # contact, brand identity, and structured positioning. Stateless on purpose —
    # the creation wizard calls this BEFORE the client exists; it returns a draft
    # the user reviews and edits.
    #
    # Fetch failures raise Operations::Errors::Invalid (the wizard surfaces a
    # friendly message). A page that is reachable but that the model can't fully
    # parse degrades to whatever fields were inferable (plus the raw signals the
    # parser already extracted: e-mail, phone, @handle, theme color).
    class ExtractClientFromUrl < Operations::Base
      def initialize(url:)
        @url = url.to_s.strip
      end

      def call
        raise Operations::Errors::Invalid, 'Informe a URL da landing page.' if @url.blank?

        digest = fetch_digest
        text = AiAdapter.complete(
          Prompts::ClientFromLandingPage.new(digest: digest),
          max_tokens: 1300, operation: 'extract_client_from_url'
        ).to_s

        data = parse(text)
        result = {
          source_url: digest[:url],
          contact: contact(data, digest),
          brand: brand(data, digest),
          positioning: Client.sanitize_positioning(data['positioning'])
        }
        logo = download_logo(digest)
        result[:logo] = logo if logo
        result
      end

      private

      def client
        @client ||= Vendors::Web::Client.new
      end

      def fetch_digest
        client.fetch_digest(@url)
      rescue Vendors::Base::Error => e
        raise Operations::Errors::Invalid, e.message
      end

      # Tries each logo candidate until one downloads as a real image (best-effort;
      # the wizard previews it and uploads it as the client's logo on save).
      def download_logo(digest)
        Array(digest[:logo_candidates]).each do |candidate|
          image = client.fetch_image(candidate)
          return image.merge(source_url: candidate) if image
        end
        nil
      end

      def parse(text)
        raw = text[/\{.*\}/m]
        raw ? JSON.parse(raw) : {}
      rescue JSON::ParserError
        {}
      end

      def contact(data, digest)
        c = data['contact'].is_a?(Hash) ? data['contact'] : {}
        {
          name: str(c['name']).presence || str(digest[:site_name]).presence || str(digest[:title]),
          company: str(c['company']),
          email: str(c['email']).presence || Array(digest[:emails]).first.to_s,
          phone: str(c['phone']).presence || Array(digest[:phones]).first.to_s
        }
      end

      def brand(data, digest)
        b = data['brand'].is_a?(Hash) ? data['brand'] : {}
        handle = str(b['default_handle']).delete('@').presence || instagram_handle(digest)
        {
          brand_voice: str(b['brand_voice']),
          default_handle: handle.to_s,
          brand_primary_color: hex(b['brand_primary_color']) || hex(digest[:theme_color]),
          brand_secondary_color: hex(b['brand_secondary_color'])
        }.compact_blank
      end

      def instagram_handle(digest)
        url = digest.dig(:socials, :instagram).to_s
        handle = url[%r{instagram\.com/([^/?#]+)}i, 1]
        handle if handle.present? && !%w[p reel reels explore].include?(handle.downcase)
      end

      # Accepts "#abc123" / "abc123" → returns "#abc123"; nil otherwise.
      def hex(value)
        v = value.to_s.strip.delete('#')
        v.match?(/\A[0-9a-fA-F]{6}\z/) ? "##{v.downcase}" : nil
      end

      def str(value) = value.to_s.strip
    end
  end
end
