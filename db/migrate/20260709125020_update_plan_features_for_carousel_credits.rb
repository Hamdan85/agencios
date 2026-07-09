# frozen_string_literal: true

# Carousels now consume prepaid credits (Pricing::CAROUSEL_CREDITS), so the plan
# feature bullets that claimed they were "included" are stale. Rewrite each plan's
# jsonb `features`: fold carrosséis into the monthly-credits line and drop/rewrite
# the "carrosséis inclusos" bullet (keeping the legendas/text-included note).
# Idempotent — after running, no bullet matches the old patterns. Data-only; `down`
# is a no-op (marketing copy, not schema).
class UpdatePlanFeaturesForCarouselCredits < ActiveRecord::Migration[8.1]
  def up
    plans = select_all('SELECT id, features FROM pricing_plans')
    plans.each do |row|
      features = parse_features(row['features'])
      updated  = transform(features)
      next if updated == features

      execute("UPDATE pricing_plans SET features = #{quote(updated.to_json)}::jsonb WHERE id = #{Integer(row['id'])}")
    end
  end

  def down
    # No-op: purely descriptive marketing copy; the prior wording isn't worth restoring.
  end

  private

  def parse_features(raw)
    raw.is_a?(String) ? JSON.parse(raw) : Array(raw)
  rescue JSON::ParserError
    []
  end

  def transform(features)
    features.filter_map do |f|
      s = f.to_s
      if s.match?(/carross/i) && s.match?(/inclus/i)
        # A carousel "included" bullet: keep it only if it also covered captions/AI
        # text (still included), rewritten; otherwise drop it entirely.
        s.match?(/legenda/i) ? 'Legendas e textos com IA inclusos' : nil
      else
        s.gsub('vídeos e imagens', 'vídeos, imagens e carrosséis')
      end
    end
  end
end
