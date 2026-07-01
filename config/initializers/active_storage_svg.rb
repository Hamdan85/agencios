# frozen_string_literal: true

# Serve SVG blobs inline as `image/svg+xml` instead of forcing them to a binary
# download.
#
# By default Rails lists `image/svg+xml` in `content_types_to_serve_as_binary`
# and omits it from `content_types_allowed_inline`, so ActiveStorage streams
# uploaded SVGs as `application/octet-stream` with `Content-Disposition:
# attachment`. That is a sensible XSS default for arbitrary user uploads, but it
# means an SVG brand logo (agencios advertises "PNG, JPG ou SVG") renders as a
# BROKEN image inside an `<img>` tag — the browser refuses to draw an SVG that
# arrives as a binary attachment.
#
# Brand assets (logos, avatars) are uploaded by workspace admins for their own
# workspace and are only ever shown through `<img>`, which does not execute
# embedded scripts, so allowing inline SVG here is acceptable for our threat
# model.
#
# We assign the config arrays (rather than mutating `ActiveStorage.*` in an
# `after_initialize` hook) so ActiveStorage's own config-copy step picks these
# values up during boot — mutating the module attributes races with that step.
Rails.application.config.active_storage.content_types_to_serve_as_binary =
  ActiveStorage.content_types_to_serve_as_binary - ["image/svg+xml"]

Rails.application.config.active_storage.content_types_allowed_inline =
  ActiveStorage.content_types_allowed_inline | ["image/svg+xml"]
