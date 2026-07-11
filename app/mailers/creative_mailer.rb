# frozen_string_literal: true

# Creative-generation outcome emails to whoever requested the generation.
class CreativeMailer < ApplicationMailer
  # The generated asset is ready.
  def ready(generation:, user:)
    @generation = generation
    @user = user
    @url = destination_url(generation)
    with_recipient_locale(user) do
      @kind_label = kind_label(generation.kind)
      mail(to: user.email, subject: I18n.t('mailers.creative.ready.subject', kind: @kind_label))
    end
  end

  # The generation failed.
  def failed(generation:, user:, reason: nil)
    @generation = generation
    @user = user
    @reason = reason
    @url = destination_url(generation)
    with_recipient_locale(user) do
      @kind_label = kind_label(generation.kind)
      mail(to: user.email, subject: I18n.t('mailers.creative.failed.subject', kind: @kind_label.downcase))
    end
  end

  private

  def kind_label(kind)
    I18n.t("mailers.creative.kinds.#{kind}", default: I18n.t('mailers.creative.kinds.default'))
  end

  def destination_url(generation)
    ticket = generation.creative&.ticket
    path = ticket ? "/tickets/#{ticket.id}" : '/estudio'
    "#{SystemConfig.app_host}#{path}"
  end
end
