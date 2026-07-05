# frozen_string_literal: true

# Dedicated page for the video VOICES (Cartesia). The voices come automatically
# from the live Cartesia library (the storyboard picks the one that fits each
# character); this page just shows what's available and lets staff import the
# catalog, set a default, force/rename specific voices, and toggle post-dubbing.
# The voice fields all live on the singleton VideoConfig — this page is only a
# nicer, full-width surface than cramming them into the engines form.
ActiveAdmin.register_page 'Vozes' do
  menu label: 'Vídeo — vozes', priority: 22

  # Pull the whole Cartesia library (PT) into the catalog so it's visible + ready.
  page_action :import, method: :post do
    count = Operations::Video::ImportVoices.call
    msg = count.positive? ? "#{count} vozes importadas da Cartesia." : 'Nenhuma voz importada (verifique a credencial cartesia.api_key).'
    redirect_to admin_vozes_path, notice: msg
  end

  # Save the voice settings (default voice, post-dub, fixed catalog) on VideoConfig.
  page_action :update_settings, method: :post do
    cfg = VideoConfig.first_or_create!
    cfg.default_voice_id  = params[:default_voice_id].to_s.strip
    cfg.voice_dub_in_post = params[:voice_dub_in_post].present?
    cfg.voice_catalog_text = params[:voice_catalog_text].to_s

    if cfg.save
      AdminAuditLog.record(staff_user: current_staff_user, action: 'edit_video_config',
                           target: cfg, metadata: { changes: cfg.saved_changes.keys },
                           ip_address: request.remote_ip)
      redirect_to admin_vozes_path, notice: 'Configurações de voz salvas.'
    else
      redirect_to admin_vozes_path, alert: cfg.errors.full_messages.to_sentence
    end
  end

  # Make a listed voice the default with one click (from a table row).
  page_action :set_default, method: :post do
    id = params[:voice_id].to_s.strip
    VideoConfig.first_or_create!.update(default_voice_id: id) if id.present?
    redirect_to admin_vozes_path, notice: "Voz padrão definida (#{id.presence || '—'})."
  end

  action_item :import_voices do
    link_to 'Importar vozes da Cartesia', admin_vozes_import_path, method: :post
  end

  content title: 'Vídeo — vozes' do
    cfg = VideoConfig.instance
    voices = begin
      Operations::Video::VoiceOptions.list
    rescue StandardError
      []
    end
    default_id = cfg.default_voice_id.to_s

    panel 'Configurações de voz' do
      para 'As vozes vêm AUTOMATICAMENTE da biblioteca da Cartesia — o storyboard escolhe a que ' \
           'combina com o personagem. Os campos abaixo são OPCIONAIS: use para forçar/renomear vozes ' \
           'ou definir um padrão. A chave da API fica nas credentials.'

      form action: admin_vozes_update_settings_path, method: :post, class: 'formtastic' do
        input type: :hidden, name: :authenticity_token, value: form_authenticity_token

        fieldset class: 'inputs' do
          ol do
            li class: 'input' do
              label 'voice_id padrão (senão usa a 1ª voz PT da Cartesia)', for: 'default_voice_id'
              input type: :text, name: :default_voice_id, id: 'default_voice_id',
                    value: default_id, autocomplete: 'off', style: 'width:100%;max-width:520px'
            end

            li class: 'input' do
              label do
                input(type: :checkbox, name: :voice_dub_in_post, value: '1', checked: cfg.voice_dub_in_post?)
                span ' Dublar na pós (garante a voz mesmo se o modelo não sincronizar)'
              end
              para 'Desligado = a voz vai como referência de áudio pro modelo lip-sincar.', class: 'inline-hints'
            end

            li class: 'input' do
              label 'Vozes fixas (opcional — uma por linha: rótulo = voice_id)', for: 'voice_catalog_text'
              textarea cfg.voice_catalog_text, name: :voice_catalog_text, id: 'voice_catalog_text',
                                               rows: 5, autocomplete: 'off', style: 'width:100%;max-width:640px',
                                               placeholder: "Feminina jovem BR = <voice_id>\nMasculina grave BR = <voice_id>"
            end
          end
        end

        div class: 'actions' do
          input type: :submit, value: 'Salvar configurações de voz', class: 'button'
        end
      end
    end

    panel "Vozes disponíveis (#{voices.size})" do
      if voices.blank?
        para 'Nenhuma voz encontrada. Clique em “Importar vozes da Cartesia” (precisa da credencial cartesia.api_key).'
      else
        table_for voices, class: 'index_table' do
          column('Padrão') do |v|
            if v[:id] == default_id
              status_tag('padrão', class: 'yes')
            else
              button_to('Usar', admin_vozes_set_default_path(voice_id: v[:id]), method: :post, class: 'button')
            end
          end
          column('Nome') { |v| v[:name] }
          column('Gênero') { |v| v[:gender] }
          column('País') { |v| v[:country] }
          column('Descrição') { |v| v[:description] }
          column('voice_id') { |v| code v[:id] }
        end
      end
    end
  end
end
