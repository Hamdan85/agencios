// ─────────────────────────────────────────────────────────────────
// lucide v1 dropped brand/trademark icons, so we hand-roll the few
// social channel glyphs we need. Each mirrors the lucide API (accepts
// `size`, `className`, and any other svg props) so it drops into the
// same call sites as a lucide icon.
// ─────────────────────────────────────────────────────────────────

export function InstagramIcon({ size = 24, className, ...props }) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      {...props}
    >
      <rect width="20" height="20" x="2" y="2" rx="5" ry="5" />
      <path d="M16 11.37A4 4 0 1 1 12.63 8 4 4 0 0 1 16 11.37z" />
      <line x1="17.5" x2="17.51" y1="6.5" y2="6.5" />
    </svg>
  )
}
