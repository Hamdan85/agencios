# frozen_string_literal: true

module Admin
  # Shared `input_html` for the AI-config model fields: tags the input for the
  # typeahead enhancer (app/javascript/admin/model_picker.js) and hands it the
  # endpoint + localized UI strings via data attributes.
  module ModelPickerHelper
    def model_picker_input_html(kind, placeholder: nil)
      {
        placeholder: placeholder,
        autocomplete: 'off',
        data: {
          model_picker: kind,
          picker_url: admin_openrouter_models_path,
          picker_loading: I18n.t('admin.model_picker.loading'),
          picker_empty: I18n.t('admin.model_picker.empty'),
          picker_more: I18n.t('admin.model_picker.load_more'),
          picker_error: I18n.t('admin.model_picker.error')
        }
      }
    end
  end
end
