# frozen_string_literal: true

module Vendors
  module OpenRouter
    module Actions
      # Poll an OpenRouter video job — returns the normalized status hash the
      # finalize path consumes. Mirrors Vendors::Heygen::Actions::GetVideoStatus.
      class GetVideoStatus
        def self.call(...) = new(...).call

        def initialize(job_id:)
          @job_id = job_id
        end

        def call
          Vendors::OpenRouter::Video.new.status(job_id: @job_id)
        end
      end
    end
  end
end
