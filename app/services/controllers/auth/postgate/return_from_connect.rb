# frozen_string_literal: true

module Controllers
  module Auth
    module Postgate
      # Handles the browser landing back from the PostGate hosted-connect flow
      # (Operations::Social::Postgate::CreateConnectUrl built the `return_url`
      # this lands on). Mirrors Controllers::Auth::Omniauth::Callback's shape:
      # verify the signed state (which carries the connecting client + requested
      # network + optional public-connect link token), then persist the newly
      # connected Profile as a SocialAccount.
      #
      # PostGate itself already ran the network's OAuth dance end-to-end before
      # redirecting here — there is no code to exchange, only the resulting
      # Profile to look up and persist.
      class ReturnFromConnect < Controllers::Base
        def initialize(state:, params:)
          @state = state
          @params = params
        end

        def call
          data = verify_state(@state)
          raise Operations::Errors::Invalid, 'state' unless data

          client = Client.find(data['client_id'])
          network = data['network'].to_s
          link = data['link']

          raise Vendors::Base::Error, @params[:connection_error].to_s if @params[:connection_error].present?

          profile = find_connected_profile(client, network)
          raise Vendors::Base::Error, 'profile_not_found' if profile.blank?

          account = Operations::Social::ConnectAccount.call(client: client, attrs: connect_attrs(network, profile))
          capture_pinterest_board!(account) if network == 'pinterest'

          { client_id: client.id, network: network, link: link }
        end

        private

        def verify_state(token)
          Rails.application.message_verifier('agencios:social_connect').verify(token.to_s)
        rescue StandardError
          nil
        end

        # The just-connected Profile: the newest `connected` profile of this
        # platform under the client's ProfileGroup. PostGate's hosted flow just
        # created it (or reactivated it), so it's the most recent by created_at.
        def find_connected_profile(client, network)
          return nil if client.postgate_group_id.blank?

          body = api_client.list_profiles(profile_group_id: client.postgate_group_id, platform: network)
          Array(body['data'])
            .select { |p| p['status'] == 'connected' }
            .max_by { |p| p['created_at'].to_s }
        end

        def connect_attrs(network, profile)
          attrs = {
            provider: network,
            connection_source: 'postgate',
            postgate_profile_id: profile['id'],
            external_user_id: profile['platform_account_id'],
            username: profile['display_name'],
            display_name: profile['display_name'],
            avatar_url: profile['avatar_url'],
            scopes: profile['scopes'] || [],
            status: :connected
          }
          # Set the same stable-identity column ConnectAccount keys the row by
          # (Operations::Social::ConnectAccount::IDENTITY_COLUMN) so a
          # postgate-sourced connection merges onto a pre-existing DIRECT row of
          # the same real account instead of creating a duplicate.
          identity_column = Operations::Social::ConnectAccount::IDENTITY_COLUMN[network]
          attrs[identity_column] = profile['platform_account_id'] if identity_column
          attrs
        end

        # Best-effort: capture the first available board so a first publish
        # doesn't have to resolve one on the fly. Boards are read live from
        # Pinterest (never cached by PostGate) — a vendor error here (e.g. the
        # scope wasn't granted yet) leaves postgate_meta empty; PublishPost
        # resolves the board lazily as a fallback.
        def capture_pinterest_board!(account)
          board = Array(api_client.list_boards(account.postgate_profile_id)['data']).first
          return if board.blank?

          account.update!(postgate_meta: account.postgate_meta.merge('board_id' => board['id']))
        rescue Vendors::Base::Error => e
          Rails.logger.warn("[Auth::Postgate] pinterest board fetch failed for account ##{account.id}: #{e.message}")
        end

        def api_client
          @api_client ||= Vendors::Postgate::Client.new
        end
      end
    end
  end
end
