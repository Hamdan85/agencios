# frozen_string_literal: true

redis_url = ENV.fetch('REDIS_URL', 'redis://localhost:6379/1')

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }

  # Load the cron schedule (sidekiq-cron) on boot.
  config.on(:startup) do
    schedule_file = Rails.root.join('config/schedule.yml')
    if File.exist?(schedule_file) && defined?(Sidekiq::Cron::Job)
      Sidekiq::Cron::Job.load_from_hash!(YAML.load_file(schedule_file))
    end
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end

# Use Sidekiq as the Active Job backend.
Rails.application.config.active_job.queue_adapter = :sidekiq
