import { useEffect, useState } from 'react'
import { Button } from '@/components/ui/button'
import { useProjectMutations } from '@/hooks/useData'
import { ProjectSettingsFields, normalizeProjectSettings } from '@/components/project/ProjectSettingsFields'

export default function ProjectSettingsTab({ project }) {
  const [settings, setSettings] = useState(() => normalizeProjectSettings(project.settings))
  const { updateSettings } = useProjectMutations()

  useEffect(() => {
    setSettings(normalizeProjectSettings(project.settings))
  }, [project.id]) // eslint-disable-line react-hooks/exhaustive-deps

  const save = () => updateSettings.mutate({ id: project.id, settings })

  return (
    <div className="flex flex-col gap-4">
      <ProjectSettingsFields value={settings} onChange={setSettings} resetKey={project.id} />
      <div className="flex justify-end">
        <Button onClick={save} disabled={updateSettings.isPending}>
          {updateSettings.isPending ? 'Salvando…' : 'Salvar configurações'}
        </Button>
      </div>
    </div>
  )
}
