import { Suspense, lazy } from 'react'
import {
  createBrowserRouter, createRoutesFromElements, RouterProvider, Route, Outlet, Navigate, useParams, useLocation,
} from 'react-router-dom'
import ProtectedRoute, { GuestRoute } from '@/components/shared/ProtectedRoute'
import Layout from '@/components/layout/Layout'
import AnalyticsBridge from '@/components/shared/AnalyticsBridge'
import { PageLoader } from '@/components/ui/feedback'
import { useOnlineStatus } from '@/hooks/useOnlineStatus'
import NotFound from '@/pages/Errors/NotFound'
import Forbidden from '@/pages/Errors/Forbidden'
import ServerError from '@/pages/Errors/ServerError'
import Offline from '@/pages/Errors/Offline'

// Old /projetos/:id links redirect to the renamed /campanhas/:id (entity rename).
function LegacyProjectRedirect() {
  const { id } = useParams()
  return <Navigate to={`/campanhas/${id}`} replace />
}

// The board merged into the tickets hub (/tickets, quadro view by default).
// Old /quadro bookmarks keep working — including ?ticket=… drawer links.
function LegacyBoardRedirect() {
  const location = useLocation()
  return <Navigate to={{ pathname: '/tickets', search: location.search }} replace />
}

const Login = lazy(() => import('@/pages/Auth/Login'))
const Register = lazy(() => import('@/pages/Auth/Register'))
const ConfirmEmailChange = lazy(() => import('@/pages/Auth/ConfirmEmailChange'))
const Account = lazy(() => import('@/pages/Account/Index'))
const Dashboard = lazy(() => import('@/pages/Dashboard/Index'))
const Calendar = lazy(() => import('@/pages/Calendar/Index'))
const Tasks = lazy(() => import('@/pages/Tasks/Index'))
const MyTasks = lazy(() => import('@/pages/Tasks/Global'))
const MyCalendar = lazy(() => import('@/pages/Calendar/Global'))
const Projects = lazy(() => import('@/pages/Projects/Index'))
const ProjectShow = lazy(() => import('@/pages/Projects/Show'))
const ReportShow = lazy(() => import('@/pages/Reports/Show'))
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
  const offline = useOnlineStatus()
  return (
    <>
      <AnalyticsBridge />
      {offline ? <Offline /> : (
        <Suspense fallback={<PageLoader />}>
          <Outlet />
        </Suspense>
      )}
    </>
  )
}

const router = createBrowserRouter(
  createRoutesFromElements(
    <Route element={<SuspenseLayout />} errorElement={<ServerError />}>
      {/* "/" is the server-rendered marketing site (PagesController#home), not React. */}

      <Route element={<GuestRoute />}>
        <Route path="/login" element={<Login />} />
        <Route path="/cadastro" element={<Register />} />
      </Route>

      {/* Public: the link mailed to a user's new address to confirm an e-mail change. */}
      <Route path="/confirmar-troca-email/:token" element={<ConfirmEmailChange />} />

      <Route path="/erro/acesso-negado" element={<Forbidden />} />

      <Route element={<ProtectedRoute />}>
        <Route element={<Layout />}>
          {/* Você — personal, cross-team views (outside any single workspace) */}
          <Route path="/minhas-tarefas" element={<MyTasks />} />
          <Route path="/meu-calendario" element={<MyCalendar />} />
          <Route path="/reunioes" element={<Meetings />} />
          <Route path="/painel" element={<Dashboard />} />
          <Route path="/calendario" element={<Calendar />} />
          <Route path="/tarefas" element={<Tasks />} />
          <Route path="/campanhas" element={<Projects />} />
          <Route path="/campanhas/:id" element={<ProjectShow />} />
          <Route path="/campanhas/:id/:tab" element={<ProjectShow />} />
          {/* Legacy URLs — the entity was renamed Projeto → Campanha; old
              bookmarks/links keep working. */}
          <Route path="/projetos" element={<Navigate to="/campanhas" replace />} />
          <Route path="/projetos/:id" element={<LegacyProjectRedirect />} />
          <Route path="/quadro" element={<LegacyBoardRedirect />} />
          <Route path="/relatorios/:id" element={<ReportShow />} />
          <Route path="/clientes" element={<Clients />} />
          <Route path="/clientes/:id" element={<ClientShow />} />
          <Route path="/clientes/:id/:tab" element={<ClientShow />} />
          <Route path="/tickets" element={<TicketsList />} />
          <Route path="/tickets/:id" element={<TicketShow />} />
          <Route path="/tickets/:id/:tab" element={<TicketShow />} />
          <Route path="/estudio" element={<Studio />} />
          <Route path="/cobrancas" element={<Invoices />} />
          <Route path="/conta" element={<Account />} />
          <Route path="/conta/:tab" element={<Account />} />
          <Route path="/configuracoes" element={<Settings />} />
          <Route path="/configuracoes/:tab" element={<Settings />} />
          <Route path="/assinatura" element={<Billing />} />
          <Route path="/assinatura/:tab" element={<Billing />} />
        </Route>
      </Route>

      {/* Unknown in-app paths render a real 404 (ProtectedRoute still bounces guests
          hitting a route that requires auth). We avoid redirecting to "/" — that path
          is now the SSR marketing site, not a React route. */}
      <Route path="*" element={<NotFound />} />
    </Route>,
  ),
)

export default function App() {
  return <RouterProvider router={router} />
}
