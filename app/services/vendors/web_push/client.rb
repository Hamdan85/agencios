# frozen_string_literal: true

require "openssl"
require "base64"
require "json"

module Vendors
  module WebPush
    # Implements RFC 8030 (Web Push), RFC 8291 (Message Encryption / aes128gcm),
    # and RFC 8292 (VAPID) using only openssl (stdlib) and faraday (already in
    # the Gemfile). No external web-push gem required.
    class Client
      CONTACT = "mailto:suporte@agencios.app"
      CURVE   = "prime256v1"
      RS      = 4096 # aes128gcm record size; single record fits any reasonable payload

      def self.send_to_user(user, title:, body:, path: "/")
        new.send_to_user(user, title:, body:, path:)
      end

      def send_to_user(user, title:, body:, path: "/")
        return unless vapid_configured?

        payload = JSON.generate({
          title:   title,
          options: { body:, icon: "/icon.png", badge: "/icon.png", data: { path: } }
        })

        user.push_subscriptions.each { |sub| deliver(sub, payload) }
      end

      private

      # ── HTTP delivery ──────────────────────────────────────────────────────────

      def deliver(subscription, payload)
        uri      = URI.parse(subscription.endpoint)
        body     = encrypt(payload, subscription.p256dh_key, subscription.auth_key)
        response = build_connection(uri).post(uri.request_uri) do |req|
          req.headers["Authorization"]    = vapid_header(uri)
          req.headers["Content-Encoding"] = "aes128gcm"
          req.headers["Content-Type"]     = "application/octet-stream"
          req.headers["TTL"]              = "86400"
          req.body = body
        end
        subscription.destroy if [ 404, 410 ].include?(response.status)
      rescue Faraday::Error => e
        status = e.response&.dig(:status)
        [ 404, 410 ].include?(status) ? subscription.destroy :
          Rails.logger.error("[WebPush] HTTP error for sub #{subscription.id}: #{e.message}")
      rescue => e
        Rails.logger.error("[WebPush] Error for sub #{subscription.id}: #{e.class}: #{e.message}")
      end

      def build_connection(uri)
        Faraday.new(url: "#{uri.scheme}://#{uri.host}") do |f|
          f.options.open_timeout = 5
          f.options.timeout      = 10
          f.adapter :net_http
        end
      end

      # ── VAPID (RFC 8292) ───────────────────────────────────────────────────────

      def vapid_header(uri)
        key      = load_vapid_private_key
        audience = "#{uri.scheme}://#{uri.host}"

        header = b64(JSON.generate({ typ: "JWT", alg: "ES256" }))
        claims = b64(JSON.generate({ aud: audience, exp: Time.now.to_i + 43_200, sub: CONTACT }))

        input = "#{header}.#{claims}"
        der   = key.sign(OpenSSL::Digest::SHA256.new, input)

        # Convert DER-encoded ECDSA signature to fixed 64-byte R||S (JWT format)
        asn1 = OpenSSL::ASN1.decode(der)
        r    = asn1.value[0].value.to_s(2).rjust(32, "\x00")[-32..]
        s    = asn1.value[1].value.to_s(2).rjust(32, "\x00")[-32..]
        jwt  = "#{input}.#{b64(r + s)}"

        pub = Base64.urlsafe_encode64(key.public_key.to_bn.to_s(2), padding: false)
        "vapid t=#{jwt},k=#{pub}"
      end

      def load_vapid_private_key
        raw = b64url_decode(Rails.application.credentials.dig(:vapid, :private_key))
        # Build SEC1 ECPrivateKey DER so we don't rely on deprecated EC setter API
        asn1 = OpenSSL::ASN1::Sequence([
          OpenSSL::ASN1::Integer(OpenSSL::BN.new(1)),
          OpenSSL::ASN1::OctetString(raw),
          OpenSSL::ASN1::ASN1Data.new([ OpenSSL::ASN1::ObjectId(CURVE) ], 0, :CONTEXT_SPECIFIC)
        ])
        OpenSSL::PKey::EC.new(asn1.to_der)
      end

      # ── Message encryption (RFC 8291, aes128gcm) ──────────────────────────────

      def encrypt(plaintext, p256dh_b64, auth_b64)
        salt       = SecureRandom.random_bytes(16)
        server_key = OpenSSL::PKey::EC.generate(CURVE)
        sub_point  = decode_ec_point(p256dh_b64)
        auth       = b64url_decode(auth_b64)

        shared_secret = server_key.dh_compute_key(sub_point)
        sub_pub_bytes = b64url_decode(p256dh_b64)
        srv_pub_bytes = server_key.public_key.to_bn.to_s(2)

        # IKM: HKDF-Extract(auth, shared) then HKDF-Expand with "WebPush: info" context
        prk = hkdf_extract(auth, shared_secret)
        ikm = hkdf_expand(prk, "WebPush: info\x00".b + sub_pub_bytes + srv_pub_bytes, 32)

        # Derive CEK (16 bytes) and nonce (12 bytes) from salt + IKM
        prk2  = hkdf_extract(salt, ikm)
        cek   = hkdf_expand(prk2, "Content-Encoding: aes128gcm\x00".b, 16)
        nonce = hkdf_expand(prk2, "Content-Encoding: nonce\x00".b, 12)

        # AES-128-GCM: plaintext || 0x02 (last-record delimiter per RFC 8291 §2.1)
        cipher = OpenSSL::Cipher.new("aes-128-gcm").tap do |c|
          c.encrypt
          c.key       = cek
          c.iv        = nonce
          c.auth_data = ""
        end
        ciphertext = cipher.update(plaintext.b + "\x02".b) + cipher.final + cipher.auth_tag

        # Record: salt(16) | rs(4BE) | idlen(1) | server_pub(65) | ciphertext
        [ salt, [ RS ].pack("N"), [ srv_pub_bytes.bytesize ].pack("C"), srv_pub_bytes, ciphertext ].join
      end

      # ── Helpers ────────────────────────────────────────────────────────────────

      # RFC 5869 HKDF-Extract: PRK = HMAC-SHA256(salt, IKM)
      def hkdf_extract(salt, ikm) = OpenSSL::HMAC.digest("SHA256", salt, ikm)

      # RFC 5869 HKDF-Expand
      def hkdf_expand(prk, info, length)
        t = "".b
        (1..((length + 31) / 32)).each_with_object("".b) do |i, out|
          t = OpenSSL::HMAC.digest("SHA256", prk, t + info + i.chr)
          out << t
        end.slice(0, length)
      end

      def decode_ec_point(b64)
        raw   = b64url_decode(b64)
        group = OpenSSL::PKey::EC::Group.new(CURVE)
        OpenSSL::PKey::EC::Point.new(group, OpenSSL::BN.new(raw, 2))
      end

      def b64url_decode(str)
        padded = str.length % 4 == 0 ? str : str.ljust((str.length + 3) & ~3, "=")
        Base64.urlsafe_decode64(padded)
      end

      def b64(str) = Base64.urlsafe_encode64(str, padding: false)

      def vapid_configured?
        Rails.application.credentials.dig(:vapid, :public_key).present? &&
          Rails.application.credentials.dig(:vapid, :private_key).present?
      end
    end
  end
end
