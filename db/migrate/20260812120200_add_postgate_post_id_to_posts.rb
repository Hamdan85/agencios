class AddPostgatePostIdToPosts < ActiveRecord::Migration[8.1]
  def change
    # PostGate's own post id (for polling/deleting/reading stats through the
    # aggregator). Nil for posts published through the direct-vendor pipeline.
    add_column :posts, :postgate_post_id, :string
    add_index :posts, :postgate_post_id
  end
end
