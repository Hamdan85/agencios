// Canonical analytics event vocabulary. One name per meaningful action, in
// snake_case so it reads identically in GTM, GA4, PostHog and the Meta Pixel.
// Call sites import `EVENTS` and pass `EVENTS.X` to `analytics.track` — never a
// raw string — so the taxonomy stays greppable and typo-proof.
//
// Conversion / activation events are the priority (acquisition → activation →
// revenue). `META_EVENTS` maps the funnel-critical ones to Meta's *standard*
// event names so Meta Ads can optimise + attribute campaigns out of the box;
// anything not mapped is sent to the pixel as a custom event.

export const EVENTS = {
  // ── Acquisition / top of funnel ──────────────────────────────
  CTA_CLICK: 'cta_click', // marketing CTA → "create account" intent (Lead)

  // ── Conversion: account + revenue ────────────────────────────
  SIGN_UP: 'sign_up', // account created (CompleteRegistration)
  TRIAL_STARTED: 'trial_started', // workspace trial begins (StartTrial)
  LOGIN: 'login',
  LOGOUT: 'logout',
  CHECKOUT_STARTED: 'checkout_started', // Stripe checkout opened (InitiateCheckout)
  SUBSCRIBE: 'subscribe', // plan selected / changed to a paid plan (Subscribe)

  // ── Activation: first real value in the product ──────────────
  CLIENT_CREATED: 'client_created',
  PROJECT_CREATED: 'project_created',
  TICKET_CREATED: 'ticket_created',
  CREATIVE_GENERATED: 'creative_generated', // also the usage-billing meter
  POST_CREATED: 'post_created',
  MEETING_SCHEDULED: 'meeting_scheduled',
  INVOICE_CREATED: 'invoice_created',
  MEMBER_INVITED: 'member_invited',

  // ── Engagement: AI surface usage ─────────────────────────────
  AI_ACTION: 'ai_action',
}

// Funnel events → Meta standard events. Keep this small and intentional; only
// the events Meta Ads can meaningfully optimise toward belong here.
export const META_EVENTS = {
  [EVENTS.CTA_CLICK]: 'Lead',
  [EVENTS.SIGN_UP]: 'CompleteRegistration',
  [EVENTS.TRIAL_STARTED]: 'StartTrial',
  [EVENTS.CHECKOUT_STARTED]: 'InitiateCheckout',
  [EVENTS.SUBSCRIBE]: 'Subscribe',
}

export default EVENTS
