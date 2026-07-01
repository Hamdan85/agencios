# frozen_string_literal: true

# Singleton config: the text-AI provider + model routing. The index bounces to
# the single row's edit form. Changing a model here takes effect immediately —
# no deploy. (The API key stays in credentials; only non-secret slugs live here.)
ActiveAdmin.register AiConfig do
  menu label: 'IA (modelos)', priority: 20

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
    f.inputs 'Provedor' do
      f.input :provider,
              as: :select,
              collection: [['Auto (detecta pela chave configurada)', ''],
                           ['OpenRouter (vários modelos)', 'openrouter'],
                           ['Anthropic (direto)', 'anthropic']],
              include_blank: false,
              hint: 'A chave da API continua nas credentials — aqui só se escolhe o provedor.'
    end
    f.inputs 'Modelo padrão' do
      f.input :default_model,
              label: 'Modelo padrão',
              hint: 'Slug do OpenRouter usado quando a operação não tem um modelo próprio. ' \
                    'Ex.: anthropic/claude-sonnet-4.5, openai/gpt-5-mini, google/gemini-2.5-flash.'
    end
    f.inputs 'Modelo por operação (deixe vazio para usar o padrão)' do
      AiConfig::OPERATIONS.each do |op|
        f.input :"op_model_#{op}",
                label: AiConfig::OP_LABELS.fetch(op, op),
                input_html: { placeholder: "padrão (#{f.object.default_model})", autocomplete: 'off' }
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
