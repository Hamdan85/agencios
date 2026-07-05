# frozen_string_literal: true

# Singleton config: the VIDEO-generation engine routing per mode. The user never
# picks an engine — the platform does, from here. Changing a model takes effect
# immediately, no deploy. (The OpenRouter key stays in credentials.)
ActiveAdmin.register VideoConfig do
  menu label: 'Vídeo (motores)', priority: 21

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
    f.inputs 'Provedor' do
      f.input :provider,
              as: :select,
              collection: [['Auto (OpenRouter)', ''], ['OpenRouter (vários modelos)', 'openrouter']],
              include_blank: false,
              hint: 'A chave da API fica nas credentials — aqui só o provedor.'
    end
    f.inputs 'Modelos de vídeo (só dois) — a plataforma renderiza a PRÉVIA no modelo de rascunho e, ' \
             'na aprovação, re-renderiza no modelo final. O modo (avatar/produto/…) não muda o modelo.' do
      f.input :draft_model,
              label: 'Modelo de rascunho (prévia)',
              input_html: { placeholder: VideoConfig::DEFAULT_DRAFT_MODEL, autocomplete: 'off' },
              hint: 'Slug de vídeo do OpenRouter rápido/barato para iterar. ' \
                    "Ex.: #{VideoConfig::DEFAULT_DRAFT_MODEL}, bytedance/seedance-2.0."
      f.input :default_model,
              label: 'Modelo final (renderização)',
              input_html: { placeholder: VideoConfig::DEFAULT_MODEL, autocomplete: 'off' },
              hint: 'Slug de vídeo do OpenRouter de melhor qualidade (áudio nativo). ' \
                    "Ex.: #{VideoConfig::DEFAULT_MODEL}, kwaivgi/kling-v3."
      f.input :max_duration_seconds, label: 'Duração máxima (s)',
                                     hint: 'Teto de segundos por vídeo (protege custo).'
    end
    f.inputs 'Provedor de música' do
      f.input :music_provider,
              as: :select,
              collection: VideoConfig::MUSIC_PROVIDERS.map { |p| [VideoConfig::MUSIC_PROVIDER_LABELS.fetch(p, p), p] },
              include_blank: false,
              hint: 'Fonte da trilha buscada pelo storyboard (Vendors::Music). Jamendo é royalty-free e ' \
                    'funciona já; Epidemic Sound é licenciado e só baixa faixas quando a conta da API tem ' \
                    'permissão de download. A chave fica nas credentials.'
    end
    f.inputs 'Trilhas de música por clima (fallback do catálogo) — usadas quando o provedor não acha nada. ' \
             'URL público do MP3 + título/crédito.' do
      VideoConfig::MUSIC_MOODS.each do |mood|
        f.input :"music_url_#{mood}",
                label: "#{VideoConfig::MUSIC_MOOD_LABELS.fetch(mood, mood)} — URL",
                input_html: { placeholder: 'https://…/track.mp3', autocomplete: 'off' }
        f.input :"music_title_#{mood}",
                label: "#{VideoConfig::MUSIC_MOOD_LABELS.fetch(mood, mood)} — título/crédito",
                input_html: { autocomplete: 'off' }
      end
    end
    f.inputs 'Vozes' do
      li class: 'input' do
        para do
          text_node 'As vozes (Cartesia) têm aba própria: '
          a 'Vídeo — vozes', href: admin_vozes_path
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
