# frozen_string_literal: true

# Shared building blocks for the branded transactional email layout.
# All emails inherit the `mailer` layout (app/views/layouts/mailer.html.erb),
# which leans on these helpers + `content_for` blocks set by each template.
module MailerHelper
  # ── Brand palette (mirrors app/frontend/styles/theme.css) ───────────────
  BRAND = {
    violet: '#7C3AED',
    violet_bright: '#8B5CF6',
    violet_deep: '#5B21B6',
    soft: '#F3EEFE',
    ink: '#18122B',
    ink_secondary: '#564F6F',
    ink_muted: '#8B86A3',
    canvas: '#F5F4FB',
    surface: '#FFFFFF',
    border: '#E8E6F2',
    pink: '#EC4899',
    success: '#10B981',
    warning: '#F59E0B',
    danger: '#F43F5E'
  }.freeze

  # The 7 funnel statuses → signature color. The label is localized per-recipient
  # via mailers.status.* (mailers already render inside with_recipient_locale).
  STATUS_COLORS = {
    'ideation' => '#F59E0B', 'scoping' => '#0EA5E9', 'production' => '#7C3AED',
    'scheduled' => '#EC4899', 'published' => '#10B981', 'retrospective' => '#6366F1',
    'done' => '#14B8A6'
  }.freeze

  # Absolute base URL for links + assets in emails (no request context).
  def app_url(path = '')
    "#{SystemConfig.app_host}#{path}"
  end

  # PNG logo mark — SVG is unreliable across email clients, so we ship the
  # rendered 192px icon served from /public.
  def logo_url
    app_url('/icon-192.png')
  end

  # ── Agency branding (client-facing emails) ──────────────────────────────
  # Client-facing mail (invoices, meeting invites, the project scope summary)
  # sets @brand_workspace so the layout renders WITH the agency's own name,
  # logo and colors instead of agencios' — the client is hearing from their
  # agency, even though agencios is the one sending it. Internal/product mail
  # (welcome, billing, assignment notifications) leaves it unset and keeps the
  # plain agencios header.
  def agency_logo_url(workspace)
    return nil unless workspace&.logo&.attached?

    Rails.application.routes.url_helpers.rails_blob_url(workspace.logo, host: SystemConfig.app_host)
  rescue StandardError
    nil
  end

  # The header gradient, built from the agency's own two brand colors —
  # same 135° treatment as agencios' own header, just re-tinted.
  def agency_gradient(workspace)
    primary = workspace.brand_primary_color.presence || BRAND[:violet]
    secondary = workspace.brand_secondary_color.presence || BRAND[:violet_deep]
    "linear-gradient(135deg,#{primary} 0%,#{secondary} 100%)"
  end

  # Single-letter fallback mark when the agency has no logo uploaded.
  def agency_initial(workspace)
    workspace.name.to_s.strip[0]&.upcase || 'A'
  end

  # Bulletproof (table-based) call-to-action button. Renders solid violet by
  # default; pass `color:` for a contextual variant (e.g. danger/success).
  def email_button(label, url, color: BRAND[:violet])
    <<~HTML.html_safe
      <table role="presentation" border="0" cellpadding="0" cellspacing="0" style="margin:8px 0 4px;">
        <tr>
          <td align="center" bgcolor="#{color}" style="border-radius:12px;">
            <a href="#{url}" target="_blank"
               style="display:inline-block;padding:13px 26px;font-family:'Inter',Helvetica,Arial,sans-serif;font-size:15px;font-weight:600;line-height:1;color:#ffffff;text-decoration:none;border-radius:12px;background:#{color};">
              #{ERB::Util.html_escape(label)}
            </a>
          </td>
        </tr>
      </table>
    HTML
  end

  # A key/value detail row used in receipts/summaries.
  def email_detail_row(label, value)
    <<~HTML.html_safe
      <tr>
        <td style="padding:6px 0;font-size:14px;color:#{BRAND[:ink_muted]};">#{ERB::Util.html_escape(label)}</td>
        <td align="right" style="padding:6px 0;font-size:14px;font-weight:600;color:#{BRAND[:ink]};">#{ERB::Util.html_escape(value)}</td>
      </tr>
    HTML
  end

  def status_label(status)
    I18n.t("mailers.status.#{status}", default: status.to_s.humanize)
  end

  def status_color(status)
    STATUS_COLORS[status.to_s] || BRAND[:violet]
  end

  # Money in cents → "R$ 1.234,56" (matches the frontend `brl()` formatter).
  def email_brl(cents)
    reais = format('%.2f', (cents || 0) / 100.0)
    int, frac = reais.split('.')
    int = int.chars.reverse.each_slice(3).map(&:join).join('.').reverse
    "R$ #{int},#{frac}"
  end

  # Date → "30/06/2026"; nil-safe.
  def email_date(value)
    return '—' if value.blank?

    value.to_date.strftime('%d/%m/%Y')
  end

  # Datetime → "30/06/2026 às 14:30"; nil-safe.
  def email_datetime(value)
    return '—' if value.blank?

    I18n.l(value, format: :email)
  end
end
