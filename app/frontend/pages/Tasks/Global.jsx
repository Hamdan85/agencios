import TasksIndex from './Index'

// Personal "Minhas tarefas" (/minhas-tarefas): the user's subtasks across every team,
// outside any single workspace.
export default function TasksGlobal() {
  return <TasksIndex scope="all_workspaces" />
}
