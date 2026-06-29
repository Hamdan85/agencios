# frozen_string_literal: true

# Ticket activity / history — a user comment, a system event, or an AI note.
class Note < ApplicationRecord
  belongs_to :workspace
  belongs_to :ticket
  belongs_to :user, optional: true

  # Files attached to a comment. Nullify on delete so they stay in the ticket
  # file list even if the comment is removed.
  has_many :attachments, dependent: :nullify

  enum :kind, { comment: 0, system: 1, ai: 2 }, prefix: true

  # System/AI notes always carry a body. A comment may instead be files-only
  # (the "body present OR files attached" rule is enforced in Notes::Create).
  validates :body, presence: true, unless: :kind_comment?

  scope :chronological, -> { order(:created_at) }

  # The workspace members this comment mentioned (authoritative for emails).
  def mentioned_users
    return User.none if mentioned_user_ids.blank?

    workspace.users.where(id: mentioned_user_ids)
  end

  # Mentions are stored in the body as `@[Display Name](user_id)` tokens. This
  # renders them back to plain `@Display Name` for non-rich surfaces (e.g. email).
  MENTION_TOKEN = /@\[([^\]]+)\]\((\d+)\)/

  def plain_body
    body.to_s.gsub(MENTION_TOKEN, '@\1')
  end
end
