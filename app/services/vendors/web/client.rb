# frozen_string_literal: true

require 'httparty'
require 'resolv'
require 'ipaddr'
require 'base64'

module Vendors
  module Web
    # Fetches a public web page (a client's landing page / site) and distills it
    # into a compact digest the AI can read: title, meta description, social links,
    # contact info, brand color hints, and the visible body copy. No third-party
    # API — a plain HTTP GET (following redirects) + an HTML parse. Used by
    # Operations::Ai::ExtractClientFromUrl.
    class Client < Vendors::Base
      USER_AGENT = 'Mozilla/5.0 (compatible; AgenciosBot/1.0; +https://agencios.app)'
      MAX_TEXT = 12_000
      MAX_IMAGE_BYTES = 1_500_000

      # Social networks we recognize from outbound links (handle extraction).
      SOCIAL_HOSTS = {
        instagram: %r{instagram\.com/([^/?#]+)}i,
        tiktok: %r{tiktok\.com/@?([^/?#]+)}i,
        youtube: %r{youtube\.com/(@[^/?#]+|c/[^/?#]+|channel/[^/?#]+)}i,
        linkedin: %r{linkedin\.com/(company|in)/([^/?#]+)}i,
        facebook: %r{facebook\.com/([^/?#]+)}i,
        x: %r{(?:twitter|x)\.com/([^/?#]+)}i
      }.freeze

      # Returns the digest Hash; raises Vendors::Base::Error on a failed fetch.
      def fetch_digest(url)
        normalized = normalize_url(url)
        raise Error, 'URL inválida.' if normalized.blank?

        guard_against_internal_address!(URI.parse(normalized).host)
        parse(fetch(normalized), normalized)
      end

      # Downloads a candidate image (logo/favicon) and returns it inline as a base64
      # data URL the wizard can preview + upload as the client's logo. Best-effort:
      # returns nil on any failure, a non-image content type, or an oversized file.
      def fetch_image(url)
        return nil if url.blank?

        guard_against_internal_address!(URI.parse(url).host)
        response = HTTParty.get(url, headers: { 'User-Agent' => USER_AGENT }, follow_redirects: true, timeout: 10)
        return nil unless response.success?

        content_type = response.headers['content-type'].to_s.split(';').first.to_s.strip.downcase
        bytes = response.body.to_s
        return nil unless content_type.start_with?('image/')
        return nil if bytes.empty? || bytes.bytesize > MAX_IMAGE_BYTES

        {
          data_url: "data:#{content_type};base64,#{Base64.strict_encode64(bytes)}",
          content_type: content_type,
          filename: image_filename(url, content_type)
        }
      rescue StandardError => e
        Rails.logger.warn("[Vendors::Web] image fetch failed for #{url}: #{e.class}: #{e.message}")
        nil
      end

      private

      # Blocks SSRF to loopback / private / link-local / metadata addresses — the
      # URL is user-supplied, so we never let it point the server at its own
      # network or a cloud metadata endpoint (169.254.169.254).
      def guard_against_internal_address!(host)
        addresses = Resolv.getaddresses(host.to_s)
        raise Error, 'Não foi possível resolver o endereço da página.' if addresses.empty?

        return unless addresses.any? { |addr| internal_ip?(addr) }

        raise Error, 'Endereço não permitido.'
      rescue Resolv::ResolvError, IPAddr::InvalidAddressError
        raise Error, 'Não foi possível resolver o endereço da página.'
      end

      def internal_ip?(addr)
        ip = IPAddr.new(addr)
        ip.loopback? || ip.private? || ip.link_local? ||
          (ip.ipv4? && ip == IPAddr.new('169.254.169.254'))
      end

      def fetch(url)
        response = HTTParty.get(
          url,
          headers: { 'User-Agent' => USER_AGENT, 'Accept' => 'text/html,application/xhtml+xml' },
          follow_redirects: true,
          timeout: 12
        )
        raise Error.new("Página retornou HTTP #{response.code}.", status: response.code) unless response.success?

        response.body.to_s
      rescue HTTParty::Error, SocketError, Timeout::Error, Net::OpenTimeout, Net::ReadTimeout,
             OpenSSL::SSL::SSLError, Errno::ECONNREFUSED => e
        raise Error, "Não foi possível acessar a página: #{e.message}"
      end

      def parse(html, base_url)
        doc = Nokogiri::HTML(html)
        doc.css('script, style, noscript, template, svg, iframe').remove

        {
          url: base_url,
          title: meta_content(doc, 'og:title').presence || doc.at_css('title')&.text&.strip,
          description: meta_content(doc, 'og:description').presence || meta_name(doc, 'description'),
          site_name: meta_content(doc, 'og:site_name'),
          theme_color: meta_name(doc, 'theme-color'),
          og_image: absolute(meta_content(doc, 'og:image'), base_url),
          logo_candidates: logo_candidates(doc, base_url),
          emails: extract_emails(doc),
          phones: extract_tels(doc),
          socials: extract_socials(doc),
          text: visible_text(doc)
        }
      end

      def normalize_url(raw)
        raw = raw.to_s.strip
        return nil if raw.blank?

        raw = "https://#{raw}" unless raw.match?(%r{\Ahttps?://}i)
        uri = URI.parse(raw)
        uri.is_a?(URI::HTTP) && uri.host.present? ? uri.to_s : nil
      rescue URI::InvalidURIError
        nil
      end

      def meta_content(doc, property)
        doc.at_css(%(meta[property="#{property}"]))&.[]('content').to_s.strip
      end

      def meta_name(doc, name)
        doc.at_css(%(meta[name="#{name}"]))&.[]('content').to_s.strip
      end

      def absolute(href, base)
        return nil if href.blank?

        URI.join(base, href).to_s
      rescue StandardError
        nil
      end

      def extract_emails(doc)
        mailto = doc.css("a[href^='mailto:']").map { |a| a['href'].to_s.sub(/\Amailto:/i, '').split('?').first }
        inline = doc.text.scan(/[\w.+-]+@[\w-]+\.[\w.-]+/)
        (mailto + inline).map { |e| e.to_s.strip.downcase }.reject(&:blank?).uniq.first(5)
      end

      def extract_tels(doc)
        doc.css("a[href^='tel:']").map { |a| a['href'].to_s.sub(/\Atel:/i, '').strip }.reject(&:blank?).uniq.first(5)
      end

      def extract_socials(doc)
        hrefs = doc.css('a[href]').map { |a| a['href'].to_s }
        SOCIAL_HOSTS.each_with_object({}) do |(network, pattern), acc|
          match = hrefs.find { |h| h.match?(pattern) }
          acc[network] = match if match
        end
      end

      def visible_text(doc)
        (doc.at_css('body') || doc).text.gsub(/\s+/, ' ').strip[0, MAX_TEXT]
      end

      # Logo/icon URLs in best-first order: an <img> that looks like a logo, the
      # apple-touch-icon (usually a clean square brand mark), the OG image, then
      # any declared favicon. The operation tries each until one downloads.
      def logo_candidates(doc, base)
        out = []
        doc.css('img[src]').each do |img|
          hint = "#{img['alt']} #{img['class']} #{img['id']} #{img['src']}".downcase
          out << img['src'] if hint.include?('logo')
        end
        out.concat(icon_hrefs(doc, 'apple-touch-icon'))
        out << meta_content(doc, 'og:image')
        out.concat(icon_hrefs(doc, 'icon'))
        out.map { |href| absolute(href, base) }.compact.uniq.first(6)
      end

      def icon_hrefs(doc, needle)
        doc.css('link[rel]').select { |l| l['rel'].to_s.downcase.include?(needle) }.map { |l| l['href'] }
      end

      def image_filename(url, content_type)
        name = File.basename(URI.parse(url).path.to_s).split('?').first.to_s
        return name if name.present? && name.include?('.')

        ext = content_type.split('/').last.to_s.sub('svg+xml', 'svg').presence || 'png'
        "logo.#{ext}"
      rescue StandardError
        'logo.png'
      end
    end
  end
end
