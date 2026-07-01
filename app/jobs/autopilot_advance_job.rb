# frozen_string_literal: true

# Drives one autopilot tick. Sets the tenant/actor context from the run (so the
# reused generation ops that read `Current.user` / `Current.workspace` work
# outside a request), then calls the state-machine driver.
class AutopilotAdvanceJob < ApplicationJob
  queue_as :default

  def perform(run_id)
    run = AutopilotRun.find_by(id: run_id)
    return unless run

    Current.workspace = run.workspace
    Current.actor = run.user
    Operations::Autopilot::Advance.call(run: run)
  ensure
    Current.reset
  end
end
