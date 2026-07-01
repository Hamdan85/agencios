# frozen_string_literal: true

# Non-sensitive infrastructure config. Secrets live in credentials.
module SystemConfig
  module_function

  def app_host
    host = ENV.fetch('APP_HOST', 'http://localhost:3000')
    return host if host.start_with?('http://', 'https://')

    "https://#{host}"
  end

  def mailer_from
    ENV.fetch('MAILER_FROM', 'agencios <nao-responda@agencios.app>')
  end

  # How many workspaces a single user may create (own). Defaults to 1. Set the
  # env var to a higher number to allow more, or to 0 / a negative value for
  # unlimited. Gates the "create workspace" action.
  def max_workspaces_per_user
    count = ENV.fetch('MAX_WORKSPACES_PER_USER', '1').to_i
    count.positive? ? count : Float::INFINITY
  end
end
