# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # Uniform seam entrypoint — exchange the OAuth code and AUTO-PICK a Page
      # (first one with CREATE_CONTENT, else the first), returning SocialAccount
      # attrs for it (a Facebook entry + an Instagram entry when the Page has a
      # linked IG business account). One pass connects BOTH networks.
      #
      # The interactive connect flow uses `Exchange` + `AccountAttrsForPage`
      # directly so the user can pick which Page to attach; this auto-pick
      # variant is the non-interactive seam (e.g. reconnect).
      #
      # Returns an Array of attribute Hashes (one per connectable network found).
      class ConnectAccount
        def self.call(...) = new(...).call

        def initialize(code:, workspace:, redirect_uri:, page_id: nil, client: nil)
          @code = code
          @workspace = workspace
          @redirect_uri = redirect_uri
          @page_id = page_id
          @client = client || Vendors::Meta::Client.new
        end

        def call
          context = Exchange.call(code: @code, redirect_uri: @redirect_uri, client: @client)
          page = pick_page(context[:pages])
          raise Vendors::Base::Error, I18n.t('api.auth.no_facebook_page') if page.nil?

          AccountAttrsForPage.call(context: context, page: page)
        end

        private

        # Prefer an explicitly requested Page; otherwise the first one whose tasks
        # include CREATE_CONTENT (facebook.md §9), else the first Page.
        def pick_page(pages)
          return pages.find { |p| p['id'] == @page_id } || pages.first if @page_id

          pages.find { |p| p['tasks'].include?('CREATE_CONTENT') } || pages.first
        end
      end
    end
  end
end
