# frozen_string_literal: true

# Serves the layout-less HTML shell that boots the React SPA. Every HTML GET
# that isn't an API/asset route falls through here (see the routes catch-all).
class SpaController < ActionController::Base
  protect_from_forgery with: :exception

  def index
    render template: 'spa/index', layout: false
  end
end
