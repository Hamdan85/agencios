# frozen_string_literal: true

module Vendors
  module Threads
    module Actions
      # Uniform seam entrypoint for the unpublish flow. The Threads Graph API does
      # not currently expose a documented endpoint for deleting a published post
      # (see docs/integrations/threads.md — no delete scope/step is granted), so
      # this always raises NotSupportedError; the caller falls back to a
      # locally-recorded unpublish with a manual-removal note.
      class DeletePost
        def self.call(...) = new(...).call

        def initialize(post)
          @post = post
        end

        def call
          raise Vendors::Base::NotSupportedError,
                I18n.t('vendors.delete_unsupported.threads')
        end
      end
    end
  end
end
