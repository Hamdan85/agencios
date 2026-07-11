# frozen_string_literal: true

# Subtask assignment notifications (the "My Tasks" feed lives at /tarefas).
class SubtaskMailer < ApplicationMailer
  def assigned(subtask:, assignee:, actor: nil)
    @subtask = subtask
    @assignee = assignee
    @actor_name = actor&.display_name
    @ticket = subtask.ticket
    @ticket_url = "#{SystemConfig.app_host}/tickets/#{@ticket.id}"
    with_recipient_locale(assignee) do
      mail(to: assignee.email, subject: I18n.t('mailers.subtask.assigned.subject', title: subtask.title))
    end
  end
end
