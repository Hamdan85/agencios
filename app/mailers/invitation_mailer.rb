# frozen_string_literal: true

# Workspace invitations. The signed token + accept link are minted by
# Controllers::Invitations::Create; this just delivers them.
class InvitationMailer < ApplicationMailer
  # @param email [String] the invitee address
  # @param role  [String] the membership role they were invited as
  # @param link  [String] the absolute accept link (/convite/:token)
  # @param workspace [Workspace] the inviting agency
  # @param inviter [User, nil] who sent the invite
  def invite(email:, role:, link:, workspace:, inviter: nil)
    @email = email
    @link = link
    @workspace = workspace
    @inviter_name = inviter&.display_name
    # The invitee has no user record yet, so render in the inviting workspace's
    # language.
    with_recipient_locale(workspace) do
      @role_label = I18n.t("mailers.invitation.roles.#{role}", default: role.to_s.humanize)
      mail(to: email, subject: I18n.t('mailers.invitation.invite.subject', workspace: workspace.name))
    end
  end
end
