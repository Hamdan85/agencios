# frozen_string_literal: true

module Tickets
  # Shared query object applying the board / list filter set to a ticket scope.
  # Used by both Controllers::Board::Index (columns) and Controllers::Tickets::Index
  # (the global list) so the two stay in lock-step. Each filter is a no-op unless
  # its param is present. `q` is a free-text search over the title, creative type
  # and the parent project's name.
  class Filters
    def self.apply(scope, params)
      new(scope, params).apply
    end

    def initialize(scope, params)
      @scope = scope
      @params = params || {}
    end

    def apply
      @scope = @scope.joins(:project) if project_join?

      filter(:project_id)  { |v| @scope.where(project_id: v) }
      filter(:client_id)   { |v| @scope.where(projects: { client_id: v }) }
      filter(:assignee_id) { |v| @scope.where(assignee_id: v) }
      filter(:creative_type) { |v| @scope.where(creative_type: v) }
      filter(:priority)    { |v| @scope.where(priority: v) }
      filter(:channel)     { |v| @scope.where("? = ANY(tickets.channels)", v) }
      filter(:q)           { |v| search(v) }

      @scope
    end

    private

    # The project table is joined once up front when any filter needs it, so the
    # client / search clauses can reference `projects.*` without a double join.
    def project_join? = present?(:client_id) || present?(:q)

    def present?(key) = @params[key].present?

    def filter(key)
      @scope = yield(@params[key]) if present?(key)
    end

    def search(term)
      like = "%#{sanitize(term)}%"
      @scope.where(
        "tickets.title ILIKE :q OR tickets.creative_type ILIKE :q OR projects.name ILIKE :q",
        q: like
      )
    end

    # Escape LIKE wildcards so a user typing "%" searches the literal character.
    def sanitize(term) = term.to_s.strip.gsub(/[\\%_]/) { |c| "\\#{c}" }
  end
end
