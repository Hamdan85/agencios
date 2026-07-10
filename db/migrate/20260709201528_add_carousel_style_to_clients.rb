class AddCarouselStyleToClients < ActiveRecord::Migration[8.1]
  def change
    # Which background the branded carousel renders with. `gradient` (the current
    # look — brand-color radial gradient) is the default so existing clients are
    # unchanged; `white` renders a white-background variant.
    add_column :clients, :carousel_style, :string, null: false, default: 'gradient'
  end
end
