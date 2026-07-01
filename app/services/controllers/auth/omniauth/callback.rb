# frozen_string_literal: true

module Controllers
  module Auth
    module Omniauth
      # Verifies the signed OAuth state (which carries the connecting client + the
      # requested network), exchanges the code via the network vendor, and either
      # persists the SocialAccount(s) or — when a Meta login exposes several Pages
      # — hands off to a Page-selection step (an agency manages many Pages, one per
      # client, so we never blindly pick one).
      #
      # Returns one of:
      #   { result: :connected, network:, client_id: }      → redirect to success
      #   { result: :select, nonce:, client_id:, network:, pages: [...] } → render picker
      class Callback < Controllers::Base
        include Omniauth::MetaConnect

        def initialize(provider:, code:, state:)
          @provider = provider.to_s
          @code = code
          @state = state
        end

        def call
          data = verify_state(@state)
          raise Operations::Errors::Invalid, 'state' unless data

          client = Client.find(data['client_id'])
          network = data['network'].to_s
          # Present only for the public per-client connect page — routes the
          # success/mobile-fallback back to /conectar/:token instead of the app.
          @link = data['link']

          facebook? ? connect_facebook(client, network) : connect_generic(client, network)
        end

        private

        # The Facebook flow (Vendors::Meta) needs Page selection; other networks
        # return a single attrs hash.
        def facebook? = @provider == 'facebook'

        # Facebook: exchange once, then let the user pick which Page to attach when
        # there is more than one. A single Page connects immediately.
        def connect_facebook(client, network)
          context = Vendors::Meta::Actions::Exchange.call(code: @code, redirect_uri: redirect_uri)
          pages = context[:pages]
          raise Vendors::Base::Error, 'Nenhuma Página do Facebook encontrada.' if pages.empty?

          if pages.one?
            persist_page!(client: client, network: network, context: context, page: pages.first)
            { result: :connected, network: network, client_id: client.id, link: @link }
          else
            offer_page_selection(client, network, context, pages)
          end
        end

        def offer_page_selection(client, network, context, pages)
          nonce = SecureRandom.hex(16)
          Rails.cache.write(
            cache_key(nonce),
            { client_id: client.id, network: network, context: context, pages: pages, link: @link },
            expires_in: CACHE_TTL
          )
          { result: :select, nonce: nonce, client_id: client.id, network: network, pages: page_options(pages) }
        end

        # Non-sensitive Page list for the picker view (no tokens).
        def page_options(pages)
          pages.map do |p|
            { id: p['id'], name: p['name'], ig_username: p['ig_username'], has_ig: p['ig_id'].present? }
          end
        end

        # Other networks return a single attrs hash (or array) — persist as-is.
        def connect_generic(client, network)
          vendor = Publishers::SocialPublisher.vendor_for_slug(@provider)
          attrs = vendor::Actions::ConnectAccount.call(
            code: @code, workspace: client.workspace, redirect_uri: redirect_uri
          )
          Array.wrap(attrs).each { |a| Operations::Social::ConnectAccount.call(client: client, attrs: a) }
          { result: :connected, network: network.presence || @provider, client_id: client.id, link: @link }
        end

        def redirect_uri
          "#{SystemConfig.app_host}/auth/#{@provider}/callback"
        end

        def verify_state(token)
          Rails.application.message_verifier('agencios:social_connect').verify(token.to_s)
        rescue StandardError
          nil
        end
      end
    end
  end
end
