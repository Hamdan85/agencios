import { BrandMark } from '@/components/brand/BrandMark'
import { DinoRunner } from './DinoRunner'

// Full-bleed layout shared by every error page (404, 403, 500, offline...).
// Renders outside <Layout/> so it works whether or not the user is authenticated.
export function ErrorScene({ code, title, description, actions }) {
  return (
    <div className="bg-shell-gradient relative flex min-h-screen items-center justify-center overflow-hidden px-6 py-12">
      <div className="absolute inset-0 bg-aurora opacity-80" />
      <main className="relative grid w-full max-w-xl justify-items-center gap-4 text-center">
        <BrandMark className="size-11 drop-shadow-md" />
        <p className="font-display text-6xl font-extrabold leading-none tracking-tight text-gradient-brand sm:text-7xl">
          {code}
        </p>
        <h1 className="font-display text-xl font-semibold text-white sm:text-2xl">{title}</h1>
        <p className="max-w-md text-sm leading-relaxed text-white/60">{description}</p>
        {actions && <div className="mt-1 flex flex-wrap items-center justify-center gap-3">{actions}</div>}
        <DinoRunner />
      </main>
    </div>
  )
}

export default ErrorScene
