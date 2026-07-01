# frozen_string_literal: true

ActiveAdmin.register Workspace do
  menu parent: 'Tenants', label: 'Workspaces', priority: 1

  actions :index, :show, :edit, :update
  # `godfathered` is the only directly-editable field (founding-user comp).
  permit_params :godfathered

  filter :name_cont, label: 'Nome contém'
  filter :slug_cont, label: 'Slug contém'
  filter :godfathered
  filter :created_at

  scope :all, default: true
  scope('Godfathered') { |s| s.where(godfathered: true) }

  index do
    selectable_column
    id_column
    column :name
    column :slug
    column('Plano') { |w| w.subscription&.plan || '—' }
    column('Status') do |w|
      sub = w.subscription
      next status_tag('godfathered', class: 'yes') if w.godfathered?
      next '—' unless sub

      status_tag(sub.status, class: (Subscription::ACTIVE_STATUSES.include?(sub.status) ? 'yes' : 'error'))
    end
    column('Acesso') do |w|
      status_tag(w.billing_active? ? 'sim' : 'bloqueado', class: w.billing_active? ? 'yes' : 'error')
    end
    column('Créditos') { |w| w.godfathered? ? '∞' : w.credits_available }
    column('Assentos') { |w| "#{w.seat_count} / #{w.seat_limit.infinite? ? '∞' : w.seat_limit}" }
    column :created_at
    actions
  end

  show do
    attributes_table do
      row :id
      row :name
      row :slug
      row('Godfathered') { |w| w.godfathered? ? status_tag('sim', class: 'yes') : 'não' }
      row('Acesso liberado') { |w| w.billing_active? ? 'Sim' : 'Não (bloqueado)' }
      row('Dono') { |w| w.owner ? link_to(w.owner.email, admin_user_path(w.owner)) : '—' }
      row('Assentos') { |w| "#{w.seat_count} / #{w.seat_limit.infinite? ? '∞' : w.seat_limit}" }
      row('Clientes') { |w| w.clients.count }
      row :created_at
    end

    panel 'Assinatura' do
      sub = workspace.subscription
      if sub
        attributes_table_for sub do
          row('Plano') { sub.plan }
          row('Status') { sub.status }
          row('Cartão no arquivo') { sub.card_on_file? ? 'Sim' : 'Não' }
          row('Assentos') { sub.seats }
          row('Trial termina') { sub.trial_ends_at }
          row('Período atual até') { sub.current_period_end }
          row('Cancela em') { sub.cancel_at }
          row('Stripe customer') { sub.stripe_customer_id }
          row('Stripe subscription') { sub.stripe_subscription_id }
        end
      else
        para 'Sem assinatura.'
      end
    end

    panel 'Créditos' do
      wallet = workspace.credit_wallet
      if wallet
        attributes_table_for wallet do
          row('Disponível') { workspace.godfathered? ? '∞ (godfathered)' : wallet.available }
          row('Do plano (granted)') { wallet.live_granted }
          row('Comprados (purchased)') { wallet.purchased_balance }
          row('Granted expira em') { wallet.granted_expires_at }
        end
      else
        para 'Sem carteira.'
      end
      div class: 'action_items' do
        span button_to('Creditar +100 (cortesia)', grant_credits_admin_workspace_path(workspace, amount: 100),
                       method: :post, class: 'button')
        span button_to('Creditar +500 (cortesia)', grant_credits_admin_workspace_path(workspace, amount: 500),
                       method: :post, class: 'button')
      end
    end

    panel 'Membros' do
      table_for workspace.memberships.includes(:user) do
        column('Usuário') { |m| link_to(m.user.email, admin_user_path(m.user)) }
        column('Papel', &:role)
      end
    end

    div class: 'action_items' do
      span link_to('Convidar membro', invite_form_admin_workspace_path(workspace), class: 'button')
      if workspace.owner && !workspace.owner.staff?
        span button_to('Personificar dono', admin_impersonate_path(workspace.owner), method: :post,
                                                                                     class: 'button', data: { confirm: "Entrar como #{workspace.owner.email}?" })
      end
    end
  end

  # ── Godfathered toggle audit ──────────────────────────────────────────────
  after_save do |workspace|
    if workspace.saved_change_to_godfathered?
      AdminAuditLog.record(
        staff_user: current_staff_user, action: 'toggle_godfathered', target: workspace,
        metadata: { godfathered: workspace.godfathered? }, ip_address: request.remote_ip
      )
    end
  end

  # ── Manual credit comp ────────────────────────────────────────────────────
  member_action :grant_credits, method: :post do
    amount = params[:amount].to_i
    Operations::Credits::Adjust.call(
      workspace: resource, amount: amount, description: "Cortesia da equipe agencios (+#{amount})"
    )
    AdminAuditLog.record(
      staff_user: current_staff_user, action: 'grant_credits', target: resource,
      metadata: { amount: amount }, ip_address: request.remote_ip
    )
    redirect_to admin_workspace_path(resource), notice: "#{amount} créditos concedidos."
  end

  # ── Invite a member to this workspace ─────────────────────────────────────
  member_action :invite_form, method: :get do
    @roles = Membership.roles.keys
    render 'admin/workspaces/invite_form'
  end

  member_action :invite, method: :post do
    email = params[:email].to_s.strip.downcase
    role  = params[:role].presence || 'member'

    redirect_to(invite_form_admin_workspace_path(resource), alert: 'Informe um e-mail.') && return if email.blank?

    token = Controllers::Invitations::Token.sign(workspace_id: resource.id, email: email, role: role)
    link  = "#{SystemConfig.app_host}/convite/#{token}"
    InvitationMailer.invite(email: email, role: role, link: link, workspace: resource,
                            inviter: current_staff_user).deliver_later

    AdminAuditLog.record(
      staff_user: current_staff_user, action: 'invite_member', target: resource,
      metadata: { email: email, role: role }, ip_address: request.remote_ip
    )
    redirect_to admin_workspace_path(resource), notice: "Convite enviado para #{email}."
  end
end
