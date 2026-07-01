# frozen_string_literal: true

require_relative 'mailer_preview_data'

# Preview at /rails/mailers/post_mailer
class PostMailerPreview < ActionMailer::Preview
  def published
    PostMailer.published(post: MailerPreviewData.post, recipient: MailerPreviewData.user)
  end

  def failed
    PostMailer.failed(post: MailerPreviewData.post, recipient: MailerPreviewData.user,
                      reason: 'Token de acesso expirado')
  end
end
