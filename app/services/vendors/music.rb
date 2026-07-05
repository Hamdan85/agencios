# frozen_string_literal: true

module Vendors
  # The MUSIC-provider adapter seam — the single call site for background-music
  # search, so the rest of the pipeline (Operations::Video::ResolveMusic) never
  # knows which vendor is active. Every provider exposes the SAME contract:
  #
  #   Actions::SearchTracks.call(query:, tags:, instrumental:) -> track hash | nil
  #   track: { url:, title:, artist:, attribution:, duration:, ... }
  #
  # The active provider is admin-editable (VideoConfig#music_provider, no deploy):
  #   * jamendo        — royalty-free / Creative Commons (the default; works today)
  #   * epidemic_sound — licensed catalog via MCP (ready, but its download needs an
  #                      entitled API account before it returns burnable tracks)
  module Music
    PROVIDERS = {
      'jamendo' => 'Vendors::Jamendo::Actions::SearchTracks',
      'epidemic_sound' => 'Vendors::EpidemicSound::Actions::SearchTracks'
    }.freeze
    DEFAULT = 'jamendo'

    # The configured provider key, falling back to the default when unset/unknown.
    def self.provider_key
      key = VideoConfig.instance.music_provider.to_s.strip.downcase
      PROVIDERS.key?(key) ? key : DEFAULT
    end

    def self.action = PROVIDERS.fetch(provider_key, PROVIDERS[DEFAULT]).constantize

    # Search the active provider for the BEST burnable track (or nil). Never
    # raises — a provider that isn't configured / errors returns nil (the caller
    # then falls back to the admin catalog, else ships the video with no music).
    def self.search(query:, tags: nil, instrumental: true)
      action.call(query: query, tags: tags, instrumental: instrumental)
    end
  end
end
