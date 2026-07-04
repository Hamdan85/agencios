# frozen_string_literal: true

# Singleton row holding the text-AI provider + model routing (admin-editable, no
# deploy). The API key stays in credentials — only the non-secret provider choice
# and model slugs live here. Read through Vendors::Ai. `instance` returns the row,
# or an unsaved defaults-populated record when the table is empty so reads never
# write.
class AiConfig < ApplicationRecord
  # Text-AI operations that route through Vendors::Ai. The video RENDER engines
  # live in VideoConfig — these are the video pipeline's TEXT agents (storyboard
  # planning, the conversational editor, the prompt-improver wand).
  OPERATIONS = %w[
    summarize_ticket fill_fields build_scope synthesize_idea synthesize_positioning
    extract_client_from_url carousel_copy project_audit draft_retrospective
    strategy_planner strategy_plan
    video_storyboard video_editor improve_video_prompt
  ].freeze

  PROVIDERS = ['', AiUsageLog::PROVIDER_OPENROUTER, AiUsageLog::PROVIDER_ANTHROPIC].freeze

  # Human labels for the per-operation model fields in ActiveAdmin.
  OP_LABELS = {
    'summarize_ticket' => 'Resumo do ticket',
    'fill_fields' => 'Preencher campos (Gerar com IA)',
    'build_scope' => 'Montar escopo (subtarefas)',
    'synthesize_idea' => 'Sintetizar ideia',
    'synthesize_positioning' => 'Sintetizar posicionamento',
    'extract_client_from_url' => 'Extrair cliente de URL',
    'carousel_copy' => 'Copy de carrossel',
    'project_audit' => 'Auditoria de campanha',
    'draft_retrospective' => 'Rascunho de retrospectiva',
    'strategy_planner' => 'Planejador de estratégia (chat)',
    'strategy_plan' => 'Planejador de estratégia (gerar plano)',
    'video_storyboard' => 'Storyboard de vídeo',
    'video_editor' => 'Editor de vídeo (chat)',
    'improve_video_prompt' => 'Melhorar prompt de vídeo'
  }.freeze

  # nil and '' both mean "auto-detect" — allow nil so a fresh first_or_create!
  # (provider column has no DB default) is valid.
  validates :provider, inclusion: { in: PROVIDERS }, allow_nil: true
  validate :operation_models_are_known

  def self.instance
    first || new
  end

  # The model to use for `operation`: a per-operation override, else the default.
  # Blank → nil (the client falls back to its own default).
  def model_for(operation)
    (operation_models[operation.to_s].presence || default_model.presence)
  end

  # 'openrouter' | 'anthropic' | '' (auto) — normalized.
  def resolved_provider
    provider.to_s.strip.downcase
  end

  # Always store a clean map: only known operations, trimmed, no blank values —
  # so no admin input (per-operation field or direct assignment) can corrupt it.
  def operation_models=(value)
    cleaned = coerce_hash(value).each_with_object({}) do |(op, model), acc|
      op = op.to_s
      model = model.to_s.strip
      acc[op] = model if OPERATIONS.include?(op) && model.present?
    end
    super(cleaned)
  end

  # --- ActiveAdmin: one text field per operation (can't mistype an operation) ---
  # `op_model_<operation>` reads/writes that operation's slug in the jsonb map.
  OPERATIONS.each do |op|
    define_method(:"op_model_#{op}") { operation_models[op] }
    define_method(:"op_model_#{op}=") { |value| self.operation_models = operation_models.merge(op => value) }
  end

  def self.op_model_attributes
    OPERATIONS.map { |op| :"op_model_#{op}" }
  end

  def self.ransackable_attributes(_auth = nil)
    %w[id provider default_model created_at updated_at]
  end

  def self.ransackable_associations(_auth = nil) = []

  private

  def coerce_hash(value)
    return {} if value.blank?
    return value.to_unsafe_h if value.respond_to?(:to_unsafe_h)

    value.respond_to?(:to_h) ? value.to_h : {}
  end

  # Safety net — the setter already drops unknown keys, so this should never fire.
  def operation_models_are_known
    bad = operation_models.keys.map(&:to_s) - OPERATIONS
    errors.add(:operation_models, "operações desconhecidas: #{bad.join(', ')}") if bad.any?
  end
end
