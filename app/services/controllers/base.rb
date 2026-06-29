# frozen_string_literal: true

module Controllers
  # Base class for HTTP-layer service objects. One class per controller action.
  # Accepts HTTP params + reads the active tenant/identity from `Current`; returns
  # the JSON payload (a Hash) the controller renders, or raises an
  # `Operations::Errors::*` / `Pundit::NotAuthorizedError` / `ActiveRecord` error
  # that `Api::V1::BaseController` maps to the right HTTP status.
  #
  # Controllers must only call these (`render_ok`/`render_created` with the result)
  # — no querying, authorization, or business logic in the controller.
  class Base
    def self.call(...)
      new(...).call
    end

    private

    # --- Active request context (mirrors Operations::Base) -------------------
    def workspace  = Current.workspace
    def user       = Current.user
    def membership = Current.membership

    # --- Authorization ------------------------------------------------------
    # Pundit, keyed on the active membership role. Raises
    # Pundit::NotAuthorizedError (→ 403) on failure.
    def authorize!(record, query)
      Pundit.authorize(membership, record, query)
    end

    def require_manager!
      return if membership&.can_manage?

      raise Operations::Errors::Forbidden, "Acesso restrito a gestores do workspace."
    end

    def require_owner!
      return if membership&.owner?

      raise Operations::Errors::Forbidden, "Acesso restrito ao owner do workspace."
    end

    def deny_guests!
      raise Operations::Errors::Forbidden if membership&.guest?
    end

    # Gate actions that consume paid resources (creative generation) behind an
    # active subscription / trial. New workspaces start trialing, so this only
    # blocks once the trial lapses or billing goes inactive. Maps to HTTP 402.
    def require_billing!
      return if workspace&.billing_active?

      raise Operations::Errors::BillingRequired
    end

    # --- Serialization ------------------------------------------------------
    def serialize(record, serializer_class, **opts)
      serializer_class.new(record, opts).as_json
    end

    def serialize_collection(records, serializer_class, **opts)
      records.map { |record| serializer_class.new(record, opts).as_json }
    end

    # --- Pagination ---------------------------------------------------------
    # Full collection by default; paginated (with a `meta` block) only when the
    # request asks for it via `page`/`per`. Lets existing callers that expect the
    # whole array keep working while new infinite-scroll clients opt in.
    def collection_payload(scope, serializer, key, params, **opts)
      unless params[:page].present? || params[:per].present?
        return { key => serialize_collection(scope, serializer) }
      end

      records, meta = paginate(scope, params, **opts)
      { key => serialize_collection(records, serializer), :meta => meta }
    end

    # Escape LIKE wildcards so a user typing "%" or "_" matches the literal char.
    def escape_like(term) = term.to_s.strip.gsub(/[\\%_]/) { |c| "\\#{c}" }

    # Slices `scope` by the `page`/`per` params (1-based) and returns
    # `[records, meta]`. `meta` carries enough for both numbered and
    # infinite-scroll clients (`has_more`). Callers serialize `records` and
    # merge `meta` into the payload.
    def paginate(scope, params, default_per: 25, max_per: 100)
      page = params[:page].to_i
      page = 1 if page < 1
      per = params[:per].to_i
      per = default_per if per <= 0
      per = max_per if per > max_per

      total = scope.except(:order).count
      records = scope.limit(per).offset((page - 1) * per)
      meta = {
        page: page, per: per, total: total,
        total_pages: (total.to_f / per).ceil,
        has_more: (page * per) < total
      }
      [records, meta]
    end
  end
end
