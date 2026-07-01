import { useRouteError } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { ErrorScene } from '@/components/errors/ErrorScene'

// Rendered by React Router's errorElement whenever a route's render or loader
// throws. Reloading re-mounts the router from scratch, which clears most
// transient render-crash state.
export default function ServerError() {
  const error = useRouteError()
  if (import.meta.env.DEV && error) console.error(error)

  return (
    <ErrorScene
      code="500"
      title="Algo deu errado por aqui"
      description="Já fomos avisados e estamos de olho nisso. Tente recarregar a página — ou desconte a frustração no jogo abaixo."
      actions={(
        <>
          <Button size="lg" onClick={() => window.location.reload()}>Recarregar</Button>
          <Button variant="ghost" size="lg" onClick={() => { window.location.href = '/painel' }}>Voltar para o painel</Button>
        </>
      )}
    />
  )
}
