# frozen_string_literal: true

require 'base64'

module Mcp
  # Turns creatives' ActiveStorage attachments into MCP content blocks so the
  # connected client (Claude / ChatGPT) can display them. Images within the size
  # cap are embedded inline as base64 `image` blocks — the portable MCP standard,
  # annotated `audience: [user]` so the client shows them to the human. Everything
  # else (video, PDF, oversized images) becomes a `resource_link` carrying the
  # blob URL.
  #
  # Inline image rendering from tool results is client-dependent (some clients
  # only surface it inside the collapsed tool-result panel), so the blob URL also
  # always remains in the tool's own JSON (`asset_urls`) as a reliable fallback.
  module Media
    MAX_INLINE_BYTES = 4.megabytes # keep base64 payloads within client limits
    MAX_IMAGES       = 8           # cap how many images we embed per call

    module_function

    # `creatives` is any enumerable of Creative records (loaded inside the tenant
    # context). Returns an array of MCP content-block hashes.
    def blocks_for(creatives)
      embedded = 0
      blocks = []

      Array(creatives).each do |creative|
        next unless creative.respond_to?(:assets) && creative.assets.attached?

        creative.assets.each do |asset|
          block =
            if inline_image?(asset) && embedded < MAX_IMAGES
              img = image_block(asset)
              embedded += 1 if img
              img || link_block(asset)
            else
              link_block(asset)
            end

          blocks << block if block
        end
      end

      blocks
    end

    def inline_image?(asset)
      asset.content_type.to_s.start_with?('image/') && asset.byte_size.to_i.positive? &&
        asset.byte_size.to_i <= MAX_INLINE_BYTES
    end

    def image_block(asset)
      {
        type: 'image',
        data: Base64.strict_encode64(asset.download),
        mimeType: asset.content_type,
        annotations: { audience: ['user'], priority: 0.9 }
      }
    rescue StandardError => e
      Rails.logger.warn("[mcp] could not inline image blob #{asset.id}: #{e.class}: #{e.message}")
      nil
    end

    def link_block(asset)
      uri = blob_url(asset)
      return nil if uri.blank?

      {
        type: 'resource_link',
        uri: uri,
        name: asset.filename.to_s,
        mimeType: asset.content_type,
        annotations: { audience: ['user'] }
      }
    end

    def blob_url(asset)
      Rails.application.routes.url_helpers.rails_blob_url(asset, host: SystemConfig.app_host)
    rescue StandardError
      nil
    end
  end
end
