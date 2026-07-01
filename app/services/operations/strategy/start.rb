# frozen_string_literal: true

module Operations
  module Strategy
    # Find (or create) the ongoing planning session for a project. A session is
    # "ongoing" while active OR proposed (a plan awaiting a decision) — we RESUME
    # it rather than starting a fresh one, so a proposed plan is never orphaned by
    # a new empty session. A proposed session wins over an active one.
    class Start < Operations::Base
      def initialize(project:, user: nil)
        @project = project
        @user = user || Current.user
      end

      def call
        sessions = @project.strategy_sessions
        sessions.status_proposed.recent.first ||
          sessions.status_active.recent.first ||
          create_session
      end

      private

      def create_session
        session = @project.strategy_sessions.new(
          workspace: @project.workspace, user: @user, status: "active"
        )
        session.push_message(role: :assistant, content: opening_message)
        session.save!
        session
      end

      # A warm, concrete opener so the drawer never starts empty — sets the client
      # by name and tells the user exactly what to say to get a plan.
      def opening_message
        client = @project.client
        who = client&.name.presence
        greeting = who ? "Vou planejar o conteúdo de **#{who}** com você." : "Vou planejar o conteúdo deste projeto com você."

        "Oi! Sou seu estrategista de conteúdo. #{greeting} " \
          "Me diga a **cadência** (ex.: 1 reel e 2 carrosséis por semana) e o **período** " \
          "(um mês, uma campanha ou contínuo) — eu já monto os tickets agendados, com as " \
          "tarefas estimadas. Já uso o contexto do cliente (marca, posicionamento e redes conectadas)."
      end
    end
  end
end
