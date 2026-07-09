class AddSentToClientAtToProjectReports < ActiveRecord::Migration[8.1]
  def change
    add_column :project_reports, :sent_to_client_at, :datetime
  end
end
