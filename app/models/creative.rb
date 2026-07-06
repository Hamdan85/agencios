# frozen_string_literal: true

# A creative asset on a ticket. `creative_type` is the registry key (the spec);
# `source` is uploaded vs generated.
class Creative < ApplicationRecord
  belongs_to :workspace
  belongs_to :ticket, optional: true
  belongs_to :client, optional: true
  belongs_to :parent, class_name: 'Creative', optional: true
  belongs_to :reviewed_by, polymorphic: true, optional: true

  has_many :versions, class_name: 'Creative', foreign_key: :parent_id, dependent: :nullify, inverse_of: :parent
  has_one  :generation, dependent: :nullify
  has_many :video_scenes, -> { ordered }, dependent: :destroy, inverse_of: :creative
  has_many_attached :assets

  enum :source, { uploaded: 0, generated: 1 }, prefix: true
  enum :status, { draft: 0, generating: 1, ready: 2, failed: 3 }, prefix: :status
  enum :approval_state,
       { pending: 'pending', approved: 'approved', changes_requested: 'changes_requested' },
       prefix: :approval, default: 'pending', scopes: false

  validates :creative_type, presence: true

  def spec = Creatives.spec_for(creative_type)

  # --- Video editor chat -----------------------------------------------------
  # The conversation for editing a generated video, stored on the creative's
  # metadata (role: 'user' | 'assistant'). Windowed so it never grows unbounded.
  CHAT_KEY = 'chat'
  CHAT_WINDOW = 100

  def chat_messages = Array((metadata || {})[CHAT_KEY])

  # `kind` tags a non-conversational message the UI renders specially
  # ('alert' = a render problem explained). `credits` stamps how many credits the
  # turn that produced this message SPENT, so the UI shows a "−N créditos" badge
  # under that exact bubble (0/absent = a free turn). `images` = reference image/
  # video URLs the user attached with the message — kept in the transcript so the
  # UI can show a clickable thumbnail and the agent can re-use them as context.
  # Plain replies omit all three.
  def push_chat_message(role:, content:, kind: nil, credits: nil, images: nil)
    entry = { 'role' => role.to_s, 'content' => content.to_s }
    entry['kind'] = kind.to_s if kind.present?
    entry['credits'] = credits.to_i if credits.to_i.positive?
    imgs = Array(images).map { |u| u.to_s.strip }.reject(&:blank?)
    entry['images'] = imgs if imgs.any?
    self.metadata = (metadata || {}).merge(CHAT_KEY => (chat_messages + [entry]).last(CHAT_WINDOW))
    entry
  end

  # The publishable media kind (image / video / carousel), used to check whether
  # a network supports this creative before posting. Derived from the actual
  # attachments first, then the creative_type / slide metadata.
  def media_kind
    attached = assets.attached? ? assets : []
    return 'video' if attached.any? { |a| a.content_type.to_s.start_with?('video/') }

    slides = metadata.is_a?(Hash) ? Array(metadata['slides']) : []
    image_count = attached.count { |a| a.content_type.to_s.start_with?('image/') }
    return 'carousel' if creative_type.to_s == 'carousel' || slides.size > 1 || image_count > 1
    return 'image' if image_count == 1 || attached.any?

    'text'
  end
end
