# frozen_string_literal: true

# Singleton config: the VIDEO-generation engine routing per mode. The user never
# picks an engine — the platform does, from here. Changing a model takes effect
# immediately, no deploy. (The OpenRouter key stays in credentials.)
ActiveAdmin.register VideoConfig do
  menu label: 'Vídeo (motores)', priority: 21

  actions :index, :edit, :update

  permit_params :provider, :default_model, :max_duration_seconds,
                *VideoConfig.mode_model_attributes, *VideoConfig.draft_model_attributes,
                *VideoConfig.music_attributes

  controller do
    def index
      redirect_to edit_admin_video_config_path(VideoConfig.first_or_create!)
    end
  end

  form do |f|
    f.semantic_errors
    f.inputs 'Provedor' do
      f.input :provider,
              as: :select,
              collection: [['Auto (OpenRouter)', ''], ['OpenRouter (vários modelos)', 'openrouter']],
              include_blank: false,
              hint: 'A chave da API fica nas credentials — aqui só o provedor.'
    end
    f.inputs 'Modelo padrão + limites' do
      f.input :default_model,
              label: 'Modelo padrão',
              hint: 'Slug de vídeo do OpenRouter usado quando o modo não tem modelo próprio. ' \
                    "Ex.: #{VideoConfig::DEFAULT_MODEL}, bytedance/seedance-2.0, kwaivgi/kling-v3."
      f.input :max_duration_seconds, label: 'Duração máxima (s)',
                                     hint: 'Teto de segundos por vídeo (protege custo).'
    end
    f.inputs 'Modelo FINAL por modo (deixe vazio para usar o padrão)' do
      VideoConfig::MODES.each do |mode|
        f.input :"model_#{mode}",
                label: VideoConfig::MODE_LABELS.fetch(mode, mode),
                input_html: { placeholder: VideoConfig::DEFAULT_MODE_MODELS[mode], autocomplete: 'off' }
      end
    end
    f.inputs 'Modelo de PRÉVIA (draft) por modo — rápido/barato; o upgrade re-renderiza no final' do
      VideoConfig::MODES.each do |mode|
        f.input :"draft_model_#{mode}",
                label: VideoConfig::MODE_LABELS.fetch(mode, mode),
                input_html: { placeholder: VideoConfig::DEFAULT_DRAFT_MODELS[mode], autocomplete: 'off' }
      end
    end
    f.inputs 'Trilhas de música por clima (base aberta / royalty-free) — o storyboard escolhe o clima; ' \
             'a música é queimada no vídeo. URL público do MP3 + título/crédito.' do
      VideoConfig::MUSIC_MOODS.each do |mood|
        f.input :"music_url_#{mood}",
                label: "#{VideoConfig::MUSIC_MOOD_LABELS.fetch(mood, mood)} — URL",
                input_html: { placeholder: 'https://…/track.mp3', autocomplete: 'off' }
        f.input :"music_title_#{mood}",
                label: "#{VideoConfig::MUSIC_MOOD_LABELS.fetch(mood, mood)} — título/crédito",
                input_html: { autocomplete: 'off' }
      end
    end
    f.actions
  end

  after_save do |cfg|
    if cfg.saved_changes? && cfg.persisted?
      AdminAuditLog.record(staff_user: current_staff_user, action: 'edit_video_config',
                           target: cfg, metadata: { changes: cfg.saved_changes.keys },
                           ip_address: request.remote_ip)
    end
  end
end
