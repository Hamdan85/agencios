# frozen_string_literal: true

# Pricing / billing setup tasks. Safe to run in dev and prod.
#
#   Dev/prod bootstrap (DB catalog only, no Stripe):
#     bin/rails pricing:seed
#
#   Full Stripe bootstrap (creates Products + Prices with lookup_key, caches ids):
#     bin/rails pricing:setup
#
#   Individual steps:
#     bin/rails pricing:stripe:provision   # create/ensure Stripe Products+Prices
#     bin/rails pricing:stripe:sync        # pull current Stripe amounts into DB
#     bin/rails pricing:show               # print the current catalog
namespace :pricing do
  desc 'Ensure the DB pricing catalog exists (idempotent, additive — safe for prod)'
  task seed: :environment do
    Pricing.seed_defaults!
    puts "✅ Catálogo garantido: #{PricingPlan.count} planos · #{PricingPack.count} pacotes"
    Rake::Task['pricing:show'].invoke
  end

  desc 'Prod: seed the catalog (plans + packs) AND push each plan to Stripe (DB = source of truth)'
  task setup: :environment do
    Pricing.seed_defaults!
    puts "✅ Catálogo garantido: #{PricingPlan.count} planos · #{PricingPack.count} pacotes"
    puts '── Sincronizando planos com o Stripe (idempotente) ─────'
    # DB price_cents is the source of truth: push each plan (create/update the
    # Product + recurring Prices, minting a new Price only when the amount
    # changed). Packs need no Stripe object — checkout uses inline price_data.
    PricingPlan.ordered.each do |plan|
      Operations::Billing::SyncPlanToStripe.call(plan: plan)
      puts "  ✅ #{plan.key}: #{plan.stripe_price_id || '—'} (R$#{plan.price_cents / 100.0}/mês)"
    rescue Vendors::Base::NotConfiguredError => e
      warn "  ⚠️  Stripe não configurado (#{e.message}). Catálogo semeado; configure stripe.secret_key e rode de novo."
      break
    rescue StandardError => e
      warn "  ⚠️  #{plan.key}: falha ao sincronizar com o Stripe — #{e.message}"
    end
    Rake::Task['pricing:show'].invoke
  end

  desc 'Print the current pricing catalog'
  task show: :environment do
    puts "\n── Planos ──────────────────────────────────────────────"
    PricingPlan.ordered.each do |p|
      annual = Pricing.annual_price_cents_for(p.key)
      printf("  %-11s R$%-7.2f/mês  R$%-8.2f/ano  %3d créditos  seats:%-6s price:%s\n",
             p.key, p.price_cents / 100.0, annual / 100.0, p.included_credits,
             (p.seats >= 1_000_000 ? '∞' : p.seats),
             p.stripe_price_id || '— (não provisionado)')
    end
    puts "  (desconto anual: #{Pricing.annual_discount_percent}%)"
    puts '── Pacotes de crédito ──────────────────────────────────'
    PricingPack.ordered.each do |p|
      printf("  %-9s R$%-7.2f  %5d créditos\n", p.key, p.price_cents / 100.0, p.credits)
    end
    puts '── Math (constantes de código, não editável no admin) ──'
    puts "  trial: #{Pricing.trial_days} dias · crédito: R$#{Pricing.credit_unit_cents / 100.0} · " \
         "markup #{Pricing.markup}× · câmbio R$#{Pricing.usd_brl} · " \
         "img #{Pricing.credits_for(kind: :image)}cr · carrossel #{Pricing.credits_for(kind: :carousel)}cr"
    puts ''
  end

  namespace :stripe do
    desc 'Create/ensure Stripe Products + Prices (lookup_key) for each plan; cache ids back'
    task provision: :environment do
      Pricing.seed_defaults!
      results = Vendors::Stripe::Actions::ProvisionPlanPrices.call
      results.each do |r|
        puts "  #{r[:action] == :created ? '🆕' : '♻️ '} #{r[:key]}: #{r[:price_id]} (R$#{(r[:amount_cents] || 0) / 100.0})"
      end
      puts "✅ Stripe provisionado (#{results.size} planos)."
    rescue Vendors::Base::NotConfiguredError => e
      warn "⚠️  Stripe não configurado (#{e.message}). Rode 'pricing:seed' para só o catálogo, " \
           'ou configure stripe.secret_key nas credentials.'
    end

    desc 'Pull current Stripe amounts (by lookup_key) into the DB catalog'
    task sync: :environment do
      updated = Vendors::Stripe::Actions::SyncPlanPrices.call
      puts "✅ #{updated} plano(s) sincronizado(s) com o Stripe."
    end

    desc 'Create a Stripe Customer for every workspace missing one (idempotent)'
    task backfill_customers: :environment do
      total = created = skipped = 0
      Workspace.includes(:subscription).find_each do |ws|
        total += 1
        if ws.subscription&.stripe_customer_id.present?
          skipped += 1
          next
        end
        id = Vendors::Stripe::Actions::EnsureCustomer.call(workspace: ws)
        created += 1
        puts "  🆕 #{ws.slug} → #{id}"
      end
      puts "✅ #{created} customer(s) criados · #{skipped} já tinham · #{total} workspaces."
    rescue Vendors::Base::NotConfiguredError => e
      warn "⚠️  Stripe não configurado (#{e.message}). Configure stripe.secret_key nas credentials."
    end
  end
end
