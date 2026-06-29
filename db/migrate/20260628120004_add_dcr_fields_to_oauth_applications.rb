# frozen_string_literal: true

# RFC 7591 Dynamic Client Registration support. Clients (e.g. Claude) register
# themselves at POST /oauth/register; we flag those rows so they can be audited
# and purged separately from first-party apps, and store the registration access
# token that authorizes later reads of the client's own registration.
class AddDcrFieldsToOauthApplications < ActiveRecord::Migration[8.1]
  def change
    add_column :oauth_applications, :dynamically_registered, :boolean, null: false, default: false
    add_column :oauth_applications, :registration_access_token, :string
    add_index  :oauth_applications, :registration_access_token, unique: true
  end
end
