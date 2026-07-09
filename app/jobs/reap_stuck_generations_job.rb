# frozen_string_literal: true

# Cron sweep: fails generations/creatives stranded mid-flight (see
# Operations::Generations::ReapStuck) so the studio/board never spins "Gerando…"
# forever after a vendor outage, request timeout, or worker death.
class ReapStuckGenerationsJob < ApplicationJob
  queue_as :low

  def perform
    Operations::Generations::ReapStuck.call
  end
end
