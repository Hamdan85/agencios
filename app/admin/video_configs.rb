# frozen_string_literal: true

# Singleton config: the VIDEO-generation engine routing per mode. The user never
# picks an engine — the platform does, from here. Changing a model takes effect
# immediately, no deploy. (The OpenRouter key stays in credentials.)
ActiveAdmin.register VideoConfig do
  menu parent: I18n.t('admin.menu.ai'), label: I18n.t('admin.video_configs.menu'), priority: 3

  actions :index, :edit, :update

  permit_params :provider, :music_provider, :default_model, :draft_model,
                :max_duration_seconds, *VideoConfig.music_attributes

  controller do
    def index
      redirect_to edit_admin_video_config_path(VideoConfig.first_or_create!)
    end
  end

  form do |f|
    f.semantic_errors
    f.inputs I18n.t('admin.video_configs.provider_section') do
      f.input :provider,
              as: :select,
              collection: [[I18n.t('admin.video_configs.provider_auto'), ''],
                           [I18n.t('admin.video_configs.provider_openrouter'), 'openrouter']],
              include_blank: false,
              hint: I18n.t('admin.video_configs.provider_hint')
    end
    f.inputs I18n.t('admin.video_configs.models_section') do
      f.input :draft_model,
              label: I18n.t('admin.video_configs.draft_model_label'),
              input_html: model_picker_input_html('video', placeholder: VideoConfig::DEFAULT_DRAFT_MODEL),
              hint: I18n.t('admin.video_configs.draft_model_hint', model: VideoConfig::DEFAULT_DRAFT_MODEL)
      f.input :default_model,
              label: I18n.t('admin.video_configs.final_model_label'),
              input_html: model_picker_input_html('video', placeholder: VideoConfig::DEFAULT_MODEL),
              hint: I18n.t('admin.video_configs.final_model_hint', model: VideoConfig::DEFAULT_MODEL)
      f.input :max_duration_seconds, label: I18n.t('admin.video_configs.max_duration_label'),
                                     hint: I18n.t('admin.video_configs.max_duration_hint')
    end
    f.inputs I18n.t('admin.video_configs.music_provider_section') do
      f.input :music_provider,
              as: :select,
              collection: VideoConfig::MUSIC_PROVIDERS.map { |p| [VideoConfig::MUSIC_PROVIDER_LABELS[p], p] },
              include_blank: false,
              hint: I18n.t('admin.video_configs.music_provider_hint')
    end
    f.inputs I18n.t('admin.video_configs.music_tracks_section') do
      VideoConfig::MUSIC_MOODS.each do |mood|
        f.input :"music_url_#{mood}",
                label: I18n.t('admin.video_configs.music_url_label', mood: VideoConfig::MUSIC_MOOD_LABELS[mood]),
                input_html: { placeholder: 'https://…/track.mp3', autocomplete: 'off' }
        f.input :"music_title_#{mood}",
                label: I18n.t('admin.video_configs.music_title_label', mood: VideoConfig::MUSIC_MOOD_LABELS[mood]),
                input_html: { autocomplete: 'off' }
      end
    end
    f.inputs I18n.t('admin.video_configs.voices_section') do
      li class: 'input' do
        para do
          text_node I18n.t('admin.video_configs.voices_link_text')
          a I18n.t('admin.video_configs.voices_link_label'), href: admin_vozes_path
          text_node '.'
        end
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
