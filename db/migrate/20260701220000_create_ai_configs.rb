# frozen_string_literal: true

# Singleton platform config for the text-AI provider + model routing, so models
# can be changed from ActiveAdmin without a deploy (the API key stays in
# credentials — secrets never go in the DB).
class CreateAiConfigs < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_configs do |t|
      t.string  :provider                          # '' = auto | 'openrouter' | 'anthropic'
      t.string  :default_model, null: false, default: 'anthropic/claude-sonnet-4.5'
      t.jsonb   :operation_models, null: false, default: {} # { operation => model_slug }

      t.timestamps
    end
  end
end
