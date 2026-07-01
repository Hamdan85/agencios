# frozen_string_literal: true

class AddUnpublishedAtToPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :unpublished_at, :datetime
  end
end
