# frozen_string_literal: true

class AddCarouselImagePaletteToClients < ActiveRecord::Migration[8.1]
  def change
    # AI-derived palette for the `image` carousel style — accent/text/scrim colors
    # chosen from the background photo (Operations::Creatives::DeriveCarouselPalette).
    # Kept SEPARATE from brand_primary_color/brand_secondary_color: the image style
    # has its own colors; gradient/white keep using the brand colors. Empty ({})
    # until an image background is set and analyzed, so existing clients are
    # unchanged and image mode falls back to the brand colors.
    add_column :clients, :carousel_image_palette, :jsonb, null: false, default: {}
  end
end
