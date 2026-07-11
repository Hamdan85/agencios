# frozen_string_literal: true

module Operations
  module Video
    # Turns a raw vendor failure reason (English, technical) into a friendly PT-BR
    # explanation the user can act on — so a render blocked by the video model's
    # safety/copyright filters reads as helpful guidance in the chat, not an
    # opaque error. Content-facing (PT-BR), per the language rules.
    module FailureNote
      module_function

      # Returns the chat message for a failed scene render. The caller
      # (PollVideoSceneJob) runs outside the request cycle, so this renders in the
      # active locale (I18n.default_locale in the job).
      def for(reason:, position:)
        I18n.t('operations.video.failure_note.header', n: position.to_i + 1, explanation: explain(reason.to_s))
      end

      def explain(reason)
        r = reason.downcase
        if r.include?('copyright')
          I18n.t('operations.video.failure_note.copyright')
        elsif r.include?('audio') || r.include?('sensitive')
          I18n.t('operations.video.failure_note.audio')
        elsif r.include?('safety') || r.include?('policy') || r.include?('moderat')
          I18n.t('operations.video.failure_note.content_rule')
        elsif r.include?('timed out') || r.include?('timeout')
          I18n.t('operations.video.failure_note.timeout')
        else
          I18n.t('operations.video.failure_note.generic')
        end
      end
    end
  end
end
