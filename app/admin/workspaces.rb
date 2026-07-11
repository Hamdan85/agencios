# frozen_string_literal: true

ActiveAdmin.register Workspace do
  menu parent: I18n.t('admin.menu.tenants'), label: I18n.t('admin.workspaces.menu'), priority: 1

  actions :index, :show, :edit, :update
  # The founding-user comp: the godfathered flag plus an optional monthly credit
  # cap for generation usage (blank = unlimited).
  permit_params :godfathered, :monthly_credit_limit

  form do |f|
    f.semantic_errors
    f.inputs I18n.t('admin.workspaces.godfathered_section') do
      f.input :godfathered,
              hint: I18n.t('admin.workspaces.godfathered_hint')
      f.input :monthly_credit_limit,
              label: I18n.t('admin.workspaces.credit_limit_label'),
              hint: I18n.t('admin.workspaces.credit_limit_hint')
    end
    f.actions
  end

  filter :name_cont, label: I18n.t('admin.workspaces.filter_name')
  filter :slug_cont, label: I18n.t('admin.workspaces.filter_slug')
  filter :godfathered
  filter :created_at

  scope :all, default: true
  scope('Godfathered') { |s| s.where(godfathered: true) }

  index do
    selectable_column
    id_column
    column :name
    column :slug
    column(I18n.t('admin.workspaces.col_plan')) { |w| w.subscription&.plan || '—' }
    column(I18n.t('admin.workspaces.col_status')) do |w|
      sub = w.subscription
      next status_tag('godfathered', class: 'yes') if w.godfathered?
      next '—' unless sub

      status_tag(sub.status, class: (Subscription::ACTIVE_STATUSES.include?(sub.status) ? 'yes' : 'error'))
    end
    column(I18n.t('admin.workspaces.col_access')) do |w|
      status_tag(w.billing_active? ? I18n.t('admin.workspaces.access_yes') : I18n.t('admin.workspaces.access_blocked'), class: w.billing_active? ? 'yes' : 'error')
    end
    column(I18n.t('admin.workspaces.col_credits')) do |w|
      if w.godfathered?
        w.monthly_credit_limit ? I18n.t('admin.workspaces.credits_per_month', available: w.credits_available, limit: w.monthly_credit_limit) : '∞'
      else
        w.credits_available
      end
    end
    column(I18n.t('admin.workspaces.col_seats')) { |w| "#{w.seat_count} / #{w.seat_limit.infinite? ? '∞' : w.seat_limit}" }
    column :created_at
    actions
  end

  show do
    attributes_table do
      row :id
      row :name
      row :slug
      row(I18n.t('admin.workspaces.row_godfathered')) { |w| w.godfathered? ? status_tag(I18n.t('admin.common.yes_tag'), class: 'yes') : I18n.t('admin.common.no_tag') }
      row(I18n.t('admin.workspaces.row_credit_limit')) do |w|
        next '—' unless w.godfathered?

        w.monthly_credit_limit ? I18n.t('admin.workspaces.credit_limit_per_month', limit: w.monthly_credit_limit) : I18n.t('admin.workspaces.unlimited')
      end
      row(I18n.t('admin.workspaces.row_access')) { |w| w.billing_active? ? I18n.t('admin.common.yes') : I18n.t('admin.workspaces.access_granted_no') }
      row(I18n.t('admin.workspaces.row_owner')) { |w| w.owner ? link_to(w.owner.email, admin_user_path(w.owner)) : '—' }
      row(I18n.t('admin.workspaces.col_seats')) { |w| "#{w.seat_count} / #{w.seat_limit.infinite? ? '∞' : w.seat_limit}" }
      row(I18n.t('admin.workspaces.row_clients')) { |w| w.clients.count }
      row :created_at
    end

    panel I18n.t('admin.workspaces.subscription_panel') do
      sub = workspace.subscription
      if sub
        attributes_table_for sub do
          row(I18n.t('admin.workspaces.sub_plan')) { sub.plan }
          row(I18n.t('admin.workspaces.sub_status')) { sub.status }
          row(I18n.t('admin.workspaces.sub_card')) { sub.card_on_file? ? I18n.t('admin.common.yes') : I18n.t('admin.common.no') }
          row(I18n.t('admin.workspaces.sub_seats')) { sub.seats }
          row(I18n.t('admin.workspaces.sub_trial_ends')) { sub.trial_ends_at }
          row(I18n.t('admin.workspaces.sub_period_end')) { sub.current_period_end }
          row(I18n.t('admin.workspaces.sub_cancel_at')) { sub.cancel_at }
          row(I18n.t('admin.workspaces.sub_customer')) { sub.stripe_customer_id }
          row(I18n.t('admin.workspaces.sub_subscription')) { sub.stripe_subscription_id }
        end
      else
        para I18n.t('admin.workspaces.no_subscription')
      end
    end

    panel I18n.t('admin.workspaces.credits_panel') do
      wallet = workspace.credit_wallet
      if wallet
        attributes_table_for wallet do
          row(I18n.t('admin.workspaces.credits_available')) do
            if workspace.credit_limited?
              I18n.t('admin.workspaces.credits_available_godfathered', available: workspace.credits_available, limit: workspace.monthly_credit_limit)
            elsif workspace.godfathered?
              I18n.t('admin.workspaces.credits_infinite_godfathered')
            else
              wallet.available
            end
          end
          row(I18n.t('admin.workspaces.credits_granted')) { wallet.live_granted }
          row(I18n.t('admin.workspaces.credits_purchased')) { wallet.purchased_balance }
          row(I18n.t('admin.workspaces.credits_granted_expires')) { wallet.granted_expires_at }
        end
      else
        para I18n.t('admin.workspaces.no_wallet')
      end
      div class: 'action_items' do
        span button_to(I18n.t('admin.workspaces.grant_100'), grant_credits_admin_workspace_path(workspace, amount: 100),
                       method: :post, class: 'button')
        span button_to(I18n.t('admin.workspaces.grant_500'), grant_credits_admin_workspace_path(workspace, amount: 500),
                       method: :post, class: 'button')
      end
    end

    panel I18n.t('admin.workspaces.members_panel') do
      table_for workspace.memberships.includes(:user) do
        column(I18n.t('admin.common.user')) { |m| link_to(m.user.email, admin_user_path(m.user)) }
        column(I18n.t('admin.common.role'), &:role)
      end
    end

    div class: 'action_items' do
      span link_to(I18n.t('admin.workspaces.invite_member'), invite_form_admin_workspace_path(workspace), class: 'button')
      if workspace.owner && !workspace.owner.staff?
        span button_to(I18n.t('admin.workspaces.impersonate_owner'), admin_impersonate_path(workspace.owner), method: :post,
                                                                                     class: 'button', data: { confirm: I18n.t('admin.common.impersonate_confirm', email: workspace.owner.email) })
      end
    end
  end

  # ── Godfathered toggle + credit-cap audit ─────────────────────────────────
  after_save do |workspace|
    if workspace.saved_change_to_godfathered?
      AdminAuditLog.record(
        staff_user: current_staff_user, action: 'toggle_godfathered', target: workspace,
        metadata: { godfathered: workspace.godfathered? }, ip_address: request.remote_ip
      )
    end

    if workspace.saved_change_to_monthly_credit_limit?
      # Apply the new cap immediately (resets this cycle's allotment to the new
      # value) rather than waiting for the next monthly refill.
      Operations::Credits::EnsureGodfatheredGrant.call(workspace: workspace, force: true) if workspace.credit_limited?
      AdminAuditLog.record(
        staff_user: current_staff_user, action: 'set_monthly_credit_limit', target: workspace,
        metadata: { monthly_credit_limit: workspace.monthly_credit_limit }, ip_address: request.remote_ip
      )
    end
  end

  # ── Manual credit comp ────────────────────────────────────────────────────
  member_action :grant_credits, method: :post do
    amount = params[:amount].to_i
    Operations::Credits::Adjust.call(
      workspace: resource, amount: amount,
      description_key: 'credits.ledger.staff_courtesy', description_params: { amount: amount }
    )
    AdminAuditLog.record(
      staff_user: current_staff_user, action: 'grant_credits', target: resource,
      metadata: { amount: amount }, ip_address: request.remote_ip
    )
    redirect_to admin_workspace_path(resource), notice: I18n.t('admin.workspaces.credits_granted_notice', amount: amount)
  end

  # ── Invite a member to this workspace ─────────────────────────────────────
  member_action :invite_form, method: :get do
    @roles = Membership.roles.keys
    render 'admin/workspaces/invite_form'
  end

  member_action :invite, method: :post do
    email = params[:email].to_s.strip.downcase
    role  = params[:role].presence || 'member'

    redirect_to(invite_form_admin_workspace_path(resource), alert: I18n.t('admin.workspaces.invite_email_required')) && return if email.blank?

    token = Controllers::Invitations::Token.sign(workspace_id: resource.id, email: email, role: role)
    link  = "#{SystemConfig.app_host}/convite/#{token}"
    InvitationMailer.invite(email: email, role: role, link: link, workspace: resource,
                            inviter: current_staff_user).deliver_later

    AdminAuditLog.record(
      staff_user: current_staff_user, action: 'invite_member', target: resource,
      metadata: { email: email, role: role }, ip_address: request.remote_ip
    )
    redirect_to admin_workspace_path(resource), notice: I18n.t('admin.workspaces.invite_sent', email: email)
  end
end
