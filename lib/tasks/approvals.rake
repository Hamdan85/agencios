# frozen_string_literal: true

namespace :approvals do
  # One-off cleanup of the GO "duplicate creative type" bug residue: de-dup the
  # stored creative_types (column + scoping field) so old tickets stop showing a
  # type twice. Read paths already .uniq, so this is cosmetic/data-hygiene only.
  desc 'De-duplicate stored creative_types on existing tickets'
  task dedup_creative_types: :environment do
    fixed = 0
    Ticket.find_each do |ticket|
      col = Array(ticket.creative_types).map(&:to_s).compact_blank
      scoping = ticket.fields['scoping'] || {}
      field = Array(scoping['creative_types']).map(&:to_s).compact_blank
      next if col == col.uniq && field == field.uniq

      scoping = scoping.merge('creative_types' => field.uniq)
      ticket.update_columns( # rubocop:disable Rails/SkipsModelValidations
        creative_types: col.uniq,
        fields: ticket.fields.merge('scoping' => scoping)
      )
      fixed += 1
    end
    puts "De-duplicated creative_types on #{fixed} ticket(s)."
  end

  # Give every unnamed creative a human name (its type label), so the client
  # approval portal shows meaningful piece names instead of raw keys.
  desc 'Backfill creatives.name from the creative type label'
  task backfill_creative_names: :environment do
    named = 0
    Creative.where(name: [nil, '']).find_each do |creative|
      label = Creatives.spec_for(creative.creative_type)&.dig(:label) || creative.creative_type
      creative.update_columns(name: label) # rubocop:disable Rails/SkipsModelValidations
      named += 1
    end
    puts "Named #{named} creative(s)."
  end
end
