# frozen_string_literal: true

# Singleton config: the IMAGE-generation model routing. The index bounces to
# the single row's edit form. Changing the model here takes effect immediately —
# no deploy. (The OpenRouter key stays in credentials; only the slug lives here.)
ActiveAdmin.register ImageConfig do
  menu parent: I18n.t('admin.menu.ai'), label: I18n.t('admin.image_configs.menu'), priority: 2

  actions :index, :edit, :update

  permit_params :default_model

  controller do
    # Singleton: always edit the one row.
    def index
      redirect_to edit_admin_image_config_path(ImageConfig.first_or_create!)
    end
  end

  form do |f|
    f.semantic_errors
    f.inputs I18n.t('admin.image_configs.model_section') do
      f.input :default_model,
              label: I18n.t('admin.image_configs.model_label'),
              input_html: { placeholder: Vendors::OpenRouter::Image::DEFAULT_MODEL, autocomplete: 'off' },
              hint: I18n.t('admin.image_configs.model_hint', model: Vendors::OpenRouter::Image::DEFAULT_MODEL)
    end
    f.actions
  end

  after_save do |cfg|
    if cfg.saved_changes? && cfg.persisted?
      AdminAuditLog.record(staff_user: current_staff_user, action: 'edit_image_config',
                           target: cfg, metadata: { changes: cfg.saved_changes.keys },
                           ip_address: request.remote_ip)
    end
  end
end
