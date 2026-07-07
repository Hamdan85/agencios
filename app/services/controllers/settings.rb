# frozen_string_literal: true

module Controllers
  # Shared helpers for the Settings::* actions.
  module Settings
    # The workspace's Setting row, created on first access (a workspace may
    # predate the settings feature or have been bootstrapped without one).
    def self.ensure_setting!(workspace)
      workspace.setting || Setting.create!(workspace: workspace)
    end
  end
end
