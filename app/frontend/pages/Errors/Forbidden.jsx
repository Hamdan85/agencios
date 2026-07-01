import { Link } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { ErrorScene } from '@/components/errors/ErrorScene'

export default function Forbidden() {
  return (
    <ErrorScene
      code="403"
      title="Você não tem acesso a essa página"
      description="Sua conta não tem permissão para ver este conteúdo. Se acha que isso é um engano, fale com um administrador do seu workspace."
      actions={(
        <>
          <Button asChild size="lg"><Link to="/painel">Voltar para o painel</Link></Button>
          <Button variant="ghost" size="lg" onClick={() => window.history.back()}>Voltar</Button>
        </>
      )}
    />
  )
}
