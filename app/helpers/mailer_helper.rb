# frozen_string_literal: true

# Shared building blocks for the branded transactional email layout.
# All emails inherit the `mailer` layout (app/views/layouts/mailer.html.erb),
# which leans on these helpers + `content_for` blocks set by each template.
module MailerHelper
  # ── Brand palette (mirrors app/frontend/styles/theme.css) ───────────────
  BRAND = {
    violet:       "#7C3AED",
    violet_bright: "#8B5CF6",
    violet_deep:  "#5B21B6",
    soft:         "#F3EEFE",
    ink:          "#18122B",
    ink_secondary: "#564F6F",
    ink_muted:    "#8B86A3",
    canvas:       "#F5F4FB",
    surface:      "#FFFFFF",
    border:       "#E8E6F2",
    pink:         "#EC4899",
    success:      "#10B981",
    warning:      "#F59E0B",
    danger:       "#F43F5E"
  }.freeze

  # The 7 funnel statuses → user-facing PT-BR label + signature color.
  STATUS_LABELS = {
    "ideation"      => ["Ideação",                 "#F59E0B"],
    "scoping"       => ["Escopo",                  "#0EA5E9"],
    "production"    => ["Produção",                "#7C3AED"],
    "scheduled"     => ["Agendado",                "#EC4899"],
    "published"     => ["Postado / Monitorando",   "#10B981"],
    "retrospective" => ["Retrospectiva",           "#6366F1"],
    "done"          => ["Concluído",               "#14B8A6"]
  }.freeze

  # Absolute base URL for links + assets in emails (no request context).
  def app_url(path = "")
    "#{SystemConfig.app_host}#{path}"
  end

  # PNG logo mark — SVG is unreliable across email clients, so we ship the
  # rendered 192px icon served from /public.
  def logo_url
    app_url("/icon-192.png")
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
    STATUS_LABELS.dig(status.to_s, 0) || status.to_s.humanize
  end

  def status_color(status)
    STATUS_LABELS.dig(status.to_s, 1) || BRAND[:violet]
  end

  # Money in cents → "R$ 1.234,56" (matches the frontend `brl()` formatter).
  def email_brl(cents)
    reais = format("%.2f", (cents || 0) / 100.0)
    int, frac = reais.split(".")
    int = int.chars.reverse.each_slice(3).map(&:join).join(".").reverse
    "R$ #{int},#{frac}"
  end

  # Date → "30/06/2026"; nil-safe.
  def email_date(value)
    return "—" if value.blank?

    value.to_date.strftime("%d/%m/%Y")
  end

  # Datetime → "30/06/2026 às 14:30"; nil-safe.
  def email_datetime(value)
    return "—" if value.blank?

    value.strftime("%d/%m/%Y às %H:%M")
  end
end
