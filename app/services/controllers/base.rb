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

      raise Operations::Errors::Forbidden, 'Acesso restrito a gestores do workspace.'
    end

    def require_owner!
      return if membership&.owner?

      raise Operations::Errors::Forbidden, 'Acesso restrito ao owner do workspace.'
    end

    def deny_guests!
      raise Operations::Errors::Forbidden if membership&.guest?
    end

    # Gate actions that consume paid resources (creative generation) behind an
    # active subscription / trial-with-card / godfathered workspace. Maps to
    # HTTP 402.
    def require_billing!
      return if workspace&.billing_active?

      raise Operations::Errors::BillingRequired
    end

    # Gate work-creating actions once seat usage exceeds the plan's limit — e.g. a
    # downgrade applied outside the app (Stripe dashboard) left the workspace with
    # more active members than the new plan allows. Existing members keep access
    # to everything else; only new tickets/projects are blocked until the owner
    # removes members or upgrades. Maps to HTTP 402.
    def require_seat_compliance!
      return unless workspace&.over_seat_limit?

      raise Operations::Errors::SeatLimitReached,
            'O workspace tem mais membros do que o plano atual permite. ' \
              'Remova membros ou faça upgrade para continuar criando tickets e projetos.'
    end

    # Preflight prepaid-credit check for a metered generation (video/image).
    # Fails fast with 402 before any Creative/Generation row or vendor call, so
    # we don't orphan records. Unlimited godfathered workspaces never need credits;
    # capped godfathered workspaces are gated on their monthly allotment like
    # everyone else. (The authoritative atomic debit still happens in the op.)
    def require_credits!(kind:, seconds: nil, engine: nil)
      return if workspace&.godfathered? && !workspace.credit_limited?

      Operations::Credits::EnsureGodfatheredGrant.call(workspace: workspace) if workspace&.credit_limited?

      needed = Pricing.credits_for(kind: kind, seconds: seconds, engine: engine)
      return if needed <= 0

      available = workspace&.credits_available.to_i
      return if available >= needed

      raise Operations::Errors::InsufficientCredits.new(required: needed, available: available)
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
      return { key => serialize_collection(scope, serializer) } unless params[:page].present? || params[:per].present?

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
