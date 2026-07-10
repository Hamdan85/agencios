# frozen_string_literal: true

module Operations
  module Notes
    # Creates a ticket note. For user comments this also resolves @-mentions
    # (filtered to actual workspace members) and attaches files — reusing
    # Operations::Attachments::Create so the files appear in the ticket file list.
    # Mentioned members are emailed asynchronously via NotifyMentionsJob.
    class Create < Operations::Base
      def initialize(ticket:, body: nil, i18n_key: nil, i18n_params: {}, user: nil, kind: :comment,
                     mentioned_user_ids: [], files: [])
        @ticket = ticket
        @body = body
        # System copy: store the key + params, render at read time in the
        # reader's locale (Note#display_body). User comments never use this.
        @i18n_key = i18n_key
        @i18n_params = i18n_params
        @user = user
        @kind = kind
        @mentioned_user_ids = Array(mentioned_user_ids)
        @files = Array(files).compact_blank
      end

      def call
        validate!

        note = Note.create!(
          workspace_id: @ticket.workspace_id,
          ticket: @ticket,
          user: @user,
          kind: @kind,
          body: @body.presence,
          i18n_key: @i18n_key,
          i18n_params: @i18n_params.transform_values(&:to_s),
          mentioned_user_ids: allowed_mention_ids
        )

        attach_files(note)
        Broadcaster.ticket(@ticket, 'note_added', note_id: note.id)
        notify_mentions(note)
        note
      end

      private

      # A comment must carry text or at least one file; system/AI notes always
      # have a body (enforced by the model).
      def validate!
        return unless @kind.to_sym == :comment
        return if @body.present? || @files.any?

        raise Operations::Errors::Invalid, I18n.t('operations.notes.empty_comment')
      end

      # ActiveStorage attach does blob I/O during save! — deliberately kept out
      # of any surrounding DB transaction to avoid holding it open across uploads.
      def attach_files(note)
        @files.each do |file|
          Operations::Attachments::Create.call(
            ticket: @ticket,
            file: file,
            uploaded_by: @user,
            note: note,
            broadcast: false
          )
        end
      end

      def allowed_mention_ids
        return [] if @mentioned_user_ids.empty?

        @ticket.workspace.memberships.where(user_id: @mentioned_user_ids).pluck(:user_id).uniq
      end

      def notify_mentions(note)
        return if note.mentioned_user_ids.blank?

        NotifyMentionsJob.perform_later(note.id)
      rescue StandardError => e
        Rails.logger.warn("[Notes::Create] could not enqueue mention notifications: #{e.message}")
      end
    end
  end
end
