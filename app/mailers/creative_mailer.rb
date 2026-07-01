# frozen_string_literal: true

# Creative-generation outcome emails to whoever requested the generation.
class CreativeMailer < ApplicationMailer
  KIND_LABELS = { "carousel" => "Carrossel", "video" => "Vídeo", "image" => "Imagem" }.freeze

  # The generated asset is ready.
  def ready(generation:, user:)
    @generation = generation
    @user = user
    @kind_label = KIND_LABELS[generation.kind.to_s] || "Criativo"
    @url = destination_url(generation)
    mail(to: user.email, subject: "#{@kind_label} pronto ✨")
  end

  # The generation failed.
  def failed(generation:, user:, reason: nil)
    @generation = generation
    @user = user
    @kind_label = KIND_LABELS[generation.kind.to_s] || "Criativo"
    @reason = reason
    @url = destination_url(generation)
    mail(to: user.email, subject: "Não foi possível gerar seu #{@kind_label.downcase}")
  end

  private

  def destination_url(generation)
    ticket = generation.creative&.ticket
    path = ticket ? "/tickets/#{ticket.id}" : "/estudio"
    "#{SystemConfig.app_host}#{path}"
  end
end
