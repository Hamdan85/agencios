# frozen_string_literal: true

class CreateImageConfigs < ActiveRecord::Migration[8.1]
  def change
    create_table :image_configs do |t|
      t.string :default_model

      t.timestamps
    end
  end
end
