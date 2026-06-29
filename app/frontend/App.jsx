import { Suspense, lazy } from 'react'
import {
  createBrowserRouter, createRoutesFromElements, RouterProvider, Route, Navigate, Outlet,
} from 'react-router-dom'
import ProtectedRoute, { GuestRoute } from '@/components/shared/ProtectedRoute'
import Layout from '@/components/layout/Layout'
import AnalyticsBridge from '@/components/shared/AnalyticsBridge'
import { PageLoader } from '@/components/ui/feedback'

const Login = lazy(() => import('@/pages/Auth/Login'))
const Register = lazy(() => import('@/pages/Auth/Register'))
const Dashboard = lazy(() => import('@/pages/Dashboard/Index'))
const Board = lazy(() => import('@/pages/Board/Index'))
const Calendar = lazy(() => import('@/pages/Calendar/Index'))
const Tasks = lazy(() => import('@/pages/Tasks/Index'))
const MyTasks = lazy(() => import('@/pages/Tasks/Global'))
const MyCalendar = lazy(() => import('@/pages/Calendar/Global'))
const Projects = lazy(() => import('@/pages/Projects/Index'))
const ProjectShow = lazy(() => import('@/pages/Projects/Show'))
const Clients = lazy(() => import('@/pages/Clients/Index'))
const ClientShow = lazy(() => import('@/pages/Clients/Show'))
const TicketsList = lazy(() => import('@/pages/Tickets/Index'))
const TicketShow = lazy(() => import('@/pages/Tickets/Show'))
const Studio = lazy(() => import('@/pages/Studio/Index'))
const Meetings = lazy(() => import('@/pages/Meetings/Index'))
const Invoices = lazy(() => import('@/pages/Invoices/Index'))
const Settings = lazy(() => import('@/pages/Settings/Index'))
const Billing = lazy(() => import('@/pages/Billing/Index'))

function SuspenseLayout() {
  return (
    <>
      <AnalyticsBridge />
      <Suspense fallback={<PageLoader />}>
        <Outlet />
      </Suspense>
    </>
  )
}

const router = createBrowserRouter(
  createRoutesFromElements(
    <Route element={<SuspenseLayout />}>
      {/* "/" is the server-rendered marketing site (PagesController#home), not React. */}

      <Route element={<GuestRoute />}>
        <Route path="/login" element={<Login />} />
        <Route path="/cadastro" element={<Register />} />
      </Route>

      <Route element={<ProtectedRoute />}>
        <Route element={<Layout />}>
          {/* Você — personal, cross-team views (outside any single workspace) */}
          <Route path="/minhas-tarefas" element={<MyTasks />} />
          <Route path="/meu-calendario" element={<MyCalendar />} />
          <Route path="/painel" element={<Dashboard />} />
          <Route path="/quadro" element={<Board />} />
          <Route path="/calendario" element={<Calendar />} />
          <Route path="/tarefas" element={<Tasks />} />
          <Route path="/projetos" element={<Projects />} />
          <Route path="/projetos/:id" element={<ProjectShow />} />
          <Route path="/clientes" element={<Clients />} />
          <Route path="/clientes/:id" element={<ClientShow />} />
          <Route path="/clientes/:id/:tab" element={<ClientShow />} />
          <Route path="/tickets" element={<TicketsList />} />
          <Route path="/tickets/:id" element={<TicketShow />} />
          <Route path="/tickets/:id/:tab" element={<TicketShow />} />
          <Route path="/estudio" element={<Studio />} />
          <Route path="/reunioes" element={<Meetings />} />
          <Route path="/cobrancas" element={<Invoices />} />
          <Route path="/configuracoes" element={<Settings />} />
          <Route path="/assinatura" element={<Billing />} />
        </Route>
      </Route>

      {/* Unknown in-app paths go to the dashboard (ProtectedRoute bounces guests to /login).
          We avoid redirecting to "/" — that path is now the SSR marketing site, not a React route. */}
      <Route path="*" element={<Navigate to="/painel" replace />} />
    </Route>,
  ),
)

export default function App() {
  return <RouterProvider router={router} />
}
