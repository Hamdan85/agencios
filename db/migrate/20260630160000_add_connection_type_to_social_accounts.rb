# frozen_string_literal: true

# Distinguishes HOW a SocialAccount was connected, so the publish/insights layer
# can route correctly. Meta accounts connected through Facebook Login publish via
# a Page token on graph.facebook.com; Instagram accounts connected through
# Instagram Login (no Facebook Page) publish via the IG user token on
# graph.instagram.com. Existing rows are all Facebook-Login era.
class AddConnectionTypeToSocialAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :social_accounts, :connection_type, :integer, null: false, default: 0
  end
end
