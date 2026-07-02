# frozen_string_literal: true

module Operations
  module Strategy
    # Find (or create) THE planning session for a project. A project has exactly
    # ONE strategist conversation, forever (unique index on project_id) — applying
    # or discarding a plan never retires it, so every open resumes the same chat
    # with its full memory. Legacy `applied`/`discarded` rows (from when sessions
    # rotated per plan cycle) are folded back to `active` on resume.
    class Start < Operations::Base
      def initialize(project:, user: nil)
        @project = project
        @user = user || Current.user
      end

      def call
        session = @project.strategy_sessions.recent.first || create_session
        session.update!(status: 'active') if session.status_applied? || session.status_discarded?
        session
      end

      private

      def create_session
        session = @project.strategy_sessions.new(
          workspace: @project.workspace, user: @user, status: 'active'
        )
        session.push_message(role: :assistant, content: opening_message)
        session.save!
        session
      rescue ActiveRecord::RecordNotUnique
        # Two concurrent opens raced past the find — the unique index kept one;
        # resume the winner.
        @project.strategy_sessions.recent.first
      end

      # A warm, concrete opener so the drawer never starts empty — sets the client
      # by name and tells the user exactly what to say to get a plan.
      def opening_message
        client = @project.client
        who = client&.name.presence
        greeting = who ? "Vou planejar o conteúdo de **#{who}** com você." : 'Vou planejar o conteúdo deste projeto com você.'

        "Oi! Sou seu estrategista de conteúdo. #{greeting} " \
          'Me diga a **cadência** (ex.: 1 reel e 2 carrosséis por semana) e o **período** ' \
          '(um mês, uma campanha ou contínuo) — eu já monto os tickets agendados, com as ' \
          'tarefas estimadas. Já uso o contexto do cliente (marca, posicionamento e redes conectadas).'
      end
    end
  end
end
