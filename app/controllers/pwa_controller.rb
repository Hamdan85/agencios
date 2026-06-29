# frozen_string_literal: true

# Serves the PWA web app manifest with the correct content type.
class PwaController < ActionController::Base
  def manifest
    render template: "pwa/manifest", formats: [ :json ], layout: false,
           content_type: "application/manifest+json"
  end
end
