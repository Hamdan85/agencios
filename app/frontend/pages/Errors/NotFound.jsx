import { Link } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { ErrorScene } from '@/components/errors/ErrorScene'

export default function NotFound() {
  return (
    <ErrorScene
      code="404"
      title="Essa página não existe"
      description="O endereço pode ter mudado ou nunca ter existido. Enquanto isso, que tal pular uns obstáculos?"
      actions={(
        <>
          <Button asChild size="lg"><Link to="/painel">Voltar para o painel</Link></Button>
          <Button variant="ghost" size="lg" onClick={() => window.history.back()}>Voltar</Button>
        </>
      )}
    />
  )
}
