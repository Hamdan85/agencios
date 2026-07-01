# frozen_string_literal: true

# Workspace invitations. The signed token + accept link are minted by
# Controllers::Invitations::Create; this just delivers them.
class InvitationMailer < ApplicationMailer
  ROLE_LABELS = {
    "owner"   => "Proprietário",
    "admin"   => "Administrador",
    "manager" => "Gerente",
    "member"  => "Membro",
    "guest"   => "Convidado"
  }.freeze

  # @param email [String] the invitee address
  # @param role  [String] the membership role they were invited as
  # @param link  [String] the absolute accept link (/convite/:token)
  # @param workspace [Workspace] the inviting agency
  # @param inviter [User, nil] who sent the invite
  def invite(email:, role:, link:, workspace:, inviter: nil)
    @email = email
    @role_label = ROLE_LABELS[role.to_s] || role.to_s.humanize
    @link = link
    @workspace = workspace
    @inviter_name = inviter&.display_name
    mail(to: email, subject: "Você foi convidado para a #{workspace.name} na agencios")
  end
end
