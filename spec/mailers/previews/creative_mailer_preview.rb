# frozen_string_literal: true

require_relative "mailer_preview_data"

# Preview at /rails/mailers/creative_mailer
class CreativeMailerPreview < ActionMailer::Preview
  def ready
    CreativeMailer.ready(generation: MailerPreviewData.generation(kind: :video), user: MailerPreviewData.user)
  end

  def failed
    CreativeMailer.failed(
      generation: MailerPreviewData.generation(kind: :carousel),
      user: MailerPreviewData.user,
      reason: "O provedor de geração excedeu o tempo limite."
    )
  end
end
