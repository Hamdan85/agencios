# frozen_string_literal: true

# Non-sensitive infrastructure config. Secrets live in credentials.
module SystemConfig
  module_function

  def app_host
    ENV.fetch("APP_HOST", "http://localhost:3000")
  end

  def mailer_from
    ENV.fetch("MAILER_FROM", "agencios <no-reply@agencios.app>")
  end
end
