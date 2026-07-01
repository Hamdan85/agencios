import { Button } from '@/components/ui/button'
import { ErrorScene } from '@/components/errors/ErrorScene'

export default function Offline() {
  return (
    <ErrorScene
      code="OFFLINE"
      title="Você está sem conexão"
      description="Não conseguimos falar com o agencios agora. Assim que a internet voltar, a página volta ao normal sozinha — ou pule uns obstáculos enquanto isso."
      actions={<Button size="lg" onClick={() => window.location.reload()}>Recarregar</Button>}
    />
  )
}
