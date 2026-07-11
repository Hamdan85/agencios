# frozen_string_literal: true

# Archived clients are read-only: they keep their history (projects, posts,
# invoices) but cannot receive NEW work — campaigns, meetings, creative
# generations. This is what makes the plan's active-client limit meaningful:
# archiving frees a slot precisely because the client stops being workable.
# Included by both service bases (Controllers::Base and Operations::Base).
module ClientGuards
  private

  # Resolves a client that can still receive new work (nil id → nil).
  def find_active_client!(client_id)
    return nil if client_id.blank?

    ensure_client_active!(workspace.clients.find(client_id))
  end

  # Raises when the given client (possibly nil) is archived.
  def ensure_client_active!(client)
    if client&.status_archived?
      raise Operations::Errors::Invalid, I18n.t('api.clients.archived', name: client.name)
    end

    client
  end
end
