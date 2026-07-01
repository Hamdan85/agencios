# frozen_string_literal: true

module Controllers
  module Auth
    module Omniauth
      # Step 2 of the Meta connect flow: the user picked which Page to attach to
      # the client. Reads the exchange result stashed under the nonce, persists the
      # Facebook (+ Instagram, when linked) SocialAccount(s), and clears the cache.
      class SelectPage < Controllers::Base
        include Omniauth::MetaConnect

        def initialize(nonce:, page_id:)
          @nonce = nonce.to_s
          @page_id = page_id.to_s
        end

        def call
          payload = Rails.cache.read(cache_key(@nonce))
          raise Operations::Errors::Invalid, 'expired' unless payload

          page = payload[:pages].find { |p| p['id'] == @page_id }
          raise Operations::Errors::Invalid, 'page' unless page

          client = Client.find(payload[:client_id])
          network = payload[:network].to_s

          persist_page!(client: client, network: network, context: payload[:context], page: page)
          Rails.cache.delete(cache_key(@nonce))

          { result: :connected, network: network, client_id: client.id, link: payload[:link] }
        end
      end
    end
  end
end
