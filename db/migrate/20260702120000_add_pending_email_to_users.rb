# frozen_string_literal: true

# Holds the not-yet-confirmed new address while a user changes their e-mail.
# The change only lands on `email` once the user clicks the confirmation link
# sent to the pending address (see Controllers::Account::ConfirmEmailChange).
class AddPendingEmailToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :pending_email, :string
  end
end
