# frozen_string_literal: true

module Operations
  module Meetings
    # Normalizes a meeting's attendee list. Entries referencing a workspace
    # member ({ user_id: }) are resolved to that user's email/name (so the
    # Calendar invite and the "appears for everyone included" rule both work);
    # plain-email guests are kept as-is with a downcased address. Entries with
    # neither a resolvable user nor an email are dropped, duplicates collapse
    # on email.
    class ResolveAttendees < Operations::Base
      def initialize(attendees, workspace: Current.workspace)
        @attendees = Array(attendees)
        @workspace = workspace
      end

      def call
        users = workspace_users
        @attendees.filter_map do |raw|
          entry = raw.to_h.transform_keys(&:to_s)
          user = users[entry['user_id'].to_i] if entry['user_id'].present?
          email = (user&.email || entry['email']).to_s.strip.downcase
          next if email.blank?

          { 'email' => email,
            'name' => (user&.name || entry['name']).presence,
            'user_id' => user&.id }.compact
        end.uniq { |a| a['email'] }
      end

      private

      def workspace_users
        @workspace.users.index_by(&:id)
      end
    end
  end
end
