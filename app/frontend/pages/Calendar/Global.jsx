import CalendarIndex from './Index'

// Personal "Meu calendário" (/meu-calendario): scheduled posts + meetings merged
// across every team, outside any single workspace.
export default function CalendarGlobal() {
  return <CalendarIndex scope="all_workspaces" />
}
