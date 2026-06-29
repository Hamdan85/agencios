# frozen_string_literal: true

module Operations
  module Clients
    # Archives a client and cascades the archive to its projects (same aggregate).
    class Archive < Operations::Base
      def initialize(client)
        @client = client
      end

      def call
        @client.update!(status: :archived)
        @client.projects.each { |project| project.update!(status: :archived) }
        @client
      end
    end
  end
end
