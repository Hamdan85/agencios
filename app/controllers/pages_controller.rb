# frozen_string_literal: true

# Server-rendered (SSR) public marketing site: Home, Como funciona,
# Funcionalidades (index + one page per feature) and Preços.
#
# These pages are intentionally NOT part of the React SPA — they are plain ERB
# rendered server-side for SEO + fast first paint, sharing the SPA's design
# system via the `marketing` Vite entrypoint. ApplicationController does not
# require authentication, so these are public.
#
# Copy lives in config/locales/pages/{pt-BR,en}.yml. The visitor locale is
# resolved anonymously (?locale / the localized /en URL scope → cookie →
# Accept-Language → default) and applied for the whole request via Localizable.
class PagesController < ApplicationController
  include Localizable

  layout 'marketing'
  before_action :persist_explicit_locale
  before_action :load_catalog
  before_action :set_alternate_urls

  def home
    @funnel                   = funnel
    @features                 = features_catalog
    @steps                    = steps
    @stats                    = stats
    @networks                 = NETWORKS
    @integrations             = INTEGRATIONS
    @context_states           = context_states
    @strategist               = strategist
    @plans                    = marketing_plans
    @trial_days               = Pricing.trial_days
    @annual_discount_percent  = Pricing.annual_discount_percent
    @credit_packs             = Pricing.credit_packs
    @credit_costs             = Pricing.public_catalog[:credit_costs]
  end

  def how_it_works
    @funnel = funnel
    @steps  = steps
  end

  def features
    @features = features_catalog
  end

  def feature
    @feature = features_catalog.find { |f| f[:slug] == params[:slug] }
    return redirect_to(features_path) if @feature.nil?

    @related = features_catalog.reject { |f| f[:slug] == @feature[:slug] }.first(3)
  end

  def pricing
    @plans                   = marketing_plans
    @faqs                    = faqs
    @trial_days              = Pricing.trial_days
    @annual_discount_percent = Pricing.annual_discount_percent
    @credit_packs            = Pricing.credit_packs
    @credit_costs            = Pricing.public_catalog[:credit_costs]
  end

  def privacy
    @updated_on = t('pages.legal.updated_on')
  end

  def terms
    @updated_on = t('pages.legal.updated_on')
  end

  private

  # ── Anonymous visitor locale resolution ─────────────────────────────
  # The localized /en URL scope injects params[:locale]; otherwise the
  # signed-in user's locale, then the persisted choice (cookie), then the
  # browser's Accept-Language, then the default. Mirrors SpaController.
  def current_locale
    normalize_locale(
      params[:locale] || session_user_locale || cookies[:locale] || header_locale
    )
  end

  def session_user_locale
    token = cookies.signed[:session_id]
    return if token.blank?

    Session.find_by(token: token)&.user&.locale
  end

  def header_locale
    accept = request.headers['Accept-Language'].to_s
    return 'pt-BR' if accept =~ /\bpt\b|pt-/i
    return 'en' if accept =~ /\ben\b|en-/i

    nil
  end

  # An explicit locale choice (the /en scope) sticks for canonical-URL
  # navigation, so an English visitor stays in English across the site.
  def persist_explicit_locale
    return if params[:locale].blank?
    return unless I18n.available_locales.map(&:to_s).include?(params[:locale].to_s)

    cookies[:locale] = { value: params[:locale].to_s, expires: 1.year, same_site: :lax }
  end

  # hreflang / og alternates: the current page's pt-BR and en absolute URLs.
  # Canonical pt-BR URLs keep the Portuguese segments; the en counterparts
  # live under the /en scope with English segments.
  EN_SEGMENTS = {
    'home' => '', 'how_it_works' => '/how-it-works', 'features' => '/features',
    'pricing' => '/pricing', 'privacy' => '/privacy', 'terms' => '/terms'
  }.freeze
  PT_SEGMENTS = {
    'home' => '/', 'how_it_works' => '/como-funciona', 'features' => '/funcionalidades',
    'pricing' => '/precos', 'privacy' => '/privacidade', 'terms' => '/termos'
  }.freeze

  def set_alternate_urls
    base = request.base_url
    if action_name == 'feature'
      pt = "/funcionalidades/#{params[:slug]}"
      en = "/en/features/#{params[:slug]}"
    else
      pt = PT_SEGMENTS[action_name] || '/'
      en = "/en#{EN_SEGMENTS[action_name]}"
    end
    @alternate_urls = { 'pt-BR' => "#{base}#{pt}", 'en' => "#{base}#{en}" }
  end

  # Available to the shared header/footer on every marketing page.
  def load_catalog
    @features_catalog = features_catalog
  end

  # ── Localized catalog builders ──────────────────────────────────────
  # Structure (keys, colors, icons) stays in code; all copy is read from the
  # locale files at request time, so it renders in the resolved locale.

  def funnel
    FUNNEL_STRUCTURE.map do |s|
      s.merge(
        label:   t("pages.funnel.#{s[:key]}.label"),
        summary: t("pages.funnel.#{s[:key]}.summary"),
        desc:    t("pages.funnel.#{s[:key]}.desc")
      )
    end
  end

  def steps
    STEP_STRUCTURE.map do |s|
      s.merge(
        title: t("pages.steps.#{s[:tkey]}.title"),
        desc:  t("pages.steps.#{s[:tkey]}.desc")
      )
    end
  end

  def stats
    STAT_STRUCTURE.map { |s| s.merge(label: t("pages.stats.#{s[:tkey]}")) }
  end

  def context_states
    CONTEXT_STATE_STRUCTURE.map do |s|
      s.merge(
        label:   t("pages.context_states.#{s[:key]}.label"),
        summary: t("pages.context_states.#{s[:key]}.summary"),
        fields:  t("pages.context_states.#{s[:key]}.fields")
      )
    end
  end

  def strategist
    {
      prompt: t('pages.strategist.prompt'),
      reply:  t('pages.strategist.reply'),
      tickets: STRATEGIST_TICKETS.map.with_index(1) do |st, i|
        st.merge(title: t("pages.strategist.tickets.t#{i}"))
      end
    }
  end

  def faqs
    days = Pricing.trial_days
    %w[trial credits free_plan multiple_agencies networks client_billing change_plan].map do |k|
      { q: t("pages.faqs.#{k}.q"), a: t("pages.faqs.#{k}.a", days: days) }
    end
  end

  def features_catalog
    FEATURE_STRUCTURE.map do |f|
      slug = f[:slug]
      f.merge(
        name:      t("pages.catalog.#{slug}.name"),
        eyebrow:   t("pages.catalog.#{slug}.eyebrow"),
        card:      t("pages.catalog.#{slug}.card"),
        headline:  t("pages.catalog.#{slug}.headline"),
        subhead:   t("pages.catalog.#{slug}.subhead"),
        points: %w[p1 p2 p3 p4].map do |p|
          { icon: f[:point_icons][%w[p1 p2 p3 p4].index(p)],
            title: t("pages.catalog.#{slug}.points.#{p}.title"),
            desc:  t("pages.catalog.#{slug}.points.#{p}.desc") }
        end,
        highlights: t("pages.catalog.#{slug}.highlights")
      )
    end
  end

  # Build the pricing cards from the CANONICAL plan catalog
  # (`Controllers::Billing::Plans` → the DB-backed `Pricing`, the same source the
  # real Stripe billing flow uses). Prices, seats and features come from there;
  # only the marketing presentation (tagline / highlight / CTA) is layered on
  # here, so an admin price change flows through to this page automatically.
  def marketing_plans
    Controllers::Billing::Plans.all.map do |plan|
      annual = Pricing.annual_price_cents_for(plan[:key])
      plan.merge(
        annual_price_cents: annual,
        annual_monthly_equivalent_cents: (annual / 12.0).round
      ).merge(plan_presentation(plan[:key]))
    end
  end

  def plan_presentation(key)
    scope = "pages.plans.presentation.#{key}"
    {
      tagline:   I18n.exists?("#{scope}.tagline") ? t("#{scope}.tagline") : nil,
      highlight: PLAN_HIGHLIGHT.fetch(key, false),
      cta:       I18n.exists?("#{scope}.cta") ? t("#{scope}.cta") : t('pages.plans.presentation.default.cta')
    }
  end

  PLAN_HIGHLIGHT = { 'agencia' => true }.freeze

  # ── The 7-stage production funnel (the board) ───────────────────────
  FUNNEL_STRUCTURE = [
    { key: 'ideation',      color: '#F59E0B', icon: 'lightbulb' },
    { key: 'scoping',       color: '#0EA5E9', icon: 'ruler' },
    { key: 'production',    color: '#7C3AED', icon: 'wand-sparkles' },
    { key: 'scheduled',     color: '#EC4899', icon: 'calendar-clock' },
    { key: 'published',     color: '#10B981', icon: 'radio' },
    { key: 'retrospective', color: '#6366F1', icon: 'chart-line' },
    { key: 'done',          color: '#14B8A6', icon: 'circle-check' }
  ].freeze

  # ── The 3-step "how it works" summary ───────────────────────────────
  STEP_STRUCTURE = [
    { n: 1, tkey: 'capture', color: '#F59E0B', icon: 'lightbulb' },
    { n: 2, tkey: 'produce', color: '#7C3AED', icon: 'wand-sparkles' },
    { n: 3, tkey: 'publish', color: '#10B981', icon: 'send' }
  ].freeze

  # ── Capability stats (the animated count-up band) ───────────────────
  STAT_STRUCTURE = [
    { value: 7,  suffix: '',  tkey: 'funnel_stages',   icon: 'workflow', color: '#7C3AED' },
    { value: 7,  suffix: '',  tkey: 'social_networks',  icon: 'share-2',  color: '#EC4899' },
    { value: 70, suffix: '+', tkey: 'ai_actions',       icon: 'sparkles', color: '#F59E0B' },
    { value: 6,  suffix: '',  tkey: 'metrics_per_post', icon: 'activity', color: '#10B981' }
  ].freeze

  # ── Supported networks (marquee + publishing section) ───────────────
  NETWORKS = [
    { name: 'Instagram', icon: 'instagram', color: '#E1306C' },
    { name: 'Facebook',  icon: 'facebook',  color: '#1877F2' },
    { name: 'Threads',   icon: 'at-sign',   color: '#18122B' },
    { name: 'TikTok',    icon: 'music',     color: '#18122B' },
    { name: 'YouTube',   icon: 'youtube',   color: '#FF0000' },
    { name: 'LinkedIn',  icon: 'linkedin',  color: '#0A66C2' },
    { name: 'X',         icon: 'twitter-x', color: '#18122B' }
  ].freeze

  # Integrations shown in the trust marquee (product + payment + AI vendors).
  INTEGRATIONS = [
    ['Instagram', 'instagram'], ['Facebook', 'facebook'], ['Threads', 'at-sign'],
    ['TikTok', 'music'], ['YouTube', 'youtube'], ['LinkedIn', 'linkedin'],
    ['X', 'twitter-x'], ['Claude', 'sparkles'],
    ['Google Meet', 'calendar-days'], ['Mercado Pago', 'receipt'], ['Stripe', 'shield-check']
  ].freeze

  # ── The contextual ticket demo (status-aware field morph) ───────────
  CONTEXT_STATE_STRUCTURE = [
    { key: 'ideation',      color: '#F59E0B', icon: 'lightbulb' },
    { key: 'scoping',       color: '#0EA5E9', icon: 'ruler' },
    { key: 'production',    color: '#7C3AED', icon: 'wand-sparkles' },
    { key: 'scheduled',     color: '#EC4899', icon: 'calendar-clock' },
    { key: 'published',     color: '#10B981', icon: 'radio' },
    { key: 'retrospective', color: '#6366F1', icon: 'chart-line' },
    { key: 'done',          color: '#14B8A6', icon: 'circle-check' }
  ].freeze

  # ── The AI Strategist demo (typewriter chat → generated tickets) ────
  STRATEGIST_TICKETS = [
    { status: 'ideation',  color: '#F59E0B' },
    { status: 'scoping',   color: '#0EA5E9' },
    { status: 'ideation',  color: '#F59E0B' },
    { status: 'scoping',   color: '#0EA5E9' },
    { status: 'ideation',  color: '#F59E0B' },
    { status: 'ideation',  color: '#F59E0B' }
  ].freeze

  # ── The main features (one detail page each) ────────────────────────
  # Structure only: slug, colors, icons. Copy is in pages.catalog.<slug>.
  FEATURE_STRUCTURE = [
    { slug: 'quadro',       color: '#EC4899', icon: 'square-kanban',
      point_icons: %w[square-kanban folder zap list-checks] },
    { slug: 'estudio',      color: '#7C3AED', icon: 'wand-sparkles',
      point_icons: %w[image video palette sparkles] },
    { slug: 'inteligencia', color: '#F59E0B', icon: 'sparkles',
      point_icons: %w[sparkles lightbulb list-checks chart-line] },
    { slug: 'publicacao',   color: '#10B981', icon: 'send',
      point_icons: %w[share-2 calendar-clock bar-chart-3 trending-up] },
    { slug: 'estrategista', color: '#6366F1', icon: 'bot',
      point_icons: %w[messages-square workflow list-checks sliders-horizontal] },
    { slug: 'relatorios',   color: '#14B8A6', icon: 'file-text',
      point_icons: %w[gauge trophy target file-text] },
    { slug: 'calendario',   color: '#0EA5E9', icon: 'calendar-days',
      point_icons: %w[calendar-days users calendar-clock clock] },
    { slug: 'cobrancas',    color: '#F97316', icon: 'receipt',
      point_icons: %w[receipt zap repeat shield-check] }
  ].freeze
end
