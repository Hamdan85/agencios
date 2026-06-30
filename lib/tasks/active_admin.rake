# frozen_string_literal: true

namespace :active_admin do
  desc "Build the Active Admin Tailwind stylesheet (app/assets/stylesheets/active_admin.css)"
  task :build_css do
    command = "npx tailwindcss -i app/assets/tailwind/active_admin.css " \
              "-o app/assets/stylesheets/active_admin.css --minify"
    puts "Building Active Admin CSS: #{command}"
    system(command, exception: true)
  end
end

# Active Admin's stylesheet is compiled by Tailwind before Propshaft digests the
# assets, so the served `active_admin.css` is real CSS rather than the raw
# `@import "tailwindcss"` source. Node is available during the Docker build.
if Rake::Task.task_defined?("assets:precompile")
  Rake::Task["assets:precompile"].enhance(["active_admin:build_css"])
end
