# frozen_string_literal: true

# Singleton config: the text-AI provider + model routing. The index bounces to
# the single row's edit form. Changing a model here takes effect immediately —
# no deploy. (The API key stays in credentials; only non-secret slugs live here.)
ActiveAdmin.register AiConfig do
  menu label: I18n.t('admin.ai_configs.menu'), priority: 20

  actions :index, :edit, :update

  permit_params :provider, :default_model, *AiConfig.op_model_attributes

  controller do
    # Singleton: always edit the one row.
    def index
      redirect_to edit_admin_ai_config_path(AiConfig.first_or_create!)
    end
  end

  form do |f|
    f.semantic_errors
    f.inputs I18n.t('admin.ai_configs.provider_section') do
      f.input :provider,
              as: :select,
              collection: [[I18n.t('admin.ai_configs.provider_auto'), ''],
                           [I18n.t('admin.ai_configs.provider_openrouter'), 'openrouter'],
                           [I18n.t('admin.ai_configs.provider_anthropic'), 'anthropic']],
              include_blank: false,
              hint: I18n.t('admin.ai_configs.provider_hint')
    end
    f.inputs I18n.t('admin.ai_configs.default_model_section') do
      f.input :default_model,
              label: I18n.t('admin.ai_configs.default_model_label'),
              hint: I18n.t('admin.ai_configs.default_model_hint')
    end
    f.inputs I18n.t('admin.ai_configs.per_operation_section') do
      AiConfig::OPERATIONS.each do |op|
        f.input :"op_model_#{op}",
                label: AiConfig::OP_LABELS[op],
                input_html: { placeholder: I18n.t('admin.ai_configs.op_placeholder', model: f.object.default_model), autocomplete: 'off' }
      end
    end
    f.actions
  end

  after_save do |cfg|
    if cfg.saved_changes? && cfg.persisted?
      AdminAuditLog.record(staff_user: current_staff_user, action: 'edit_ai_config',
                           target: cfg, metadata: { changes: cfg.saved_changes.keys },
                           ip_address: request.remote_ip)
    end
  end
end
