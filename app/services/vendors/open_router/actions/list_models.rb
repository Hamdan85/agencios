# frozen_string_literal: true

module Vendors
  module OpenRouter
    module Actions
      # Searches + paginates the (cached) OpenRouter catalog for the admin model
      # pickers. Matches the query against the model id and display name.
      #
      # Returns { results: [{ id:, name: }], has_more:, total: }.
      class ListModels
        def self.call(...) = new(...).call

        PER_PAGE = 20

        def initialize(kind:, query: nil, page: 1)
          @kind  = kind.to_s
          @query = query.to_s.strip.downcase
          @page  = [page.to_i, 1].max
        end

        def call
          all = Vendors::OpenRouter::Catalog.new.models(kind: @kind)
          filtered =
            if @query.blank?
              all
            else
              all.select { |m| m[:id].downcase.include?(@query) || m[:name].downcase.include?(@query) }
            end

          offset = (@page - 1) * PER_PAGE
          {
            results: filtered.slice(offset, PER_PAGE) || [],
            has_more: filtered.size > offset + PER_PAGE,
            total: filtered.size
          }
        end
      end
    end
  end
end
