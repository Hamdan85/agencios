# frozen_string_literal: true

# Public status page for a Meta data-deletion request. The data-deletion callback
# returns a URL pointing here with a `code`; the user visits to confirm. Deletion
# is synchronous, so this always reports complete.
class DataDeletionController < ActionController::Base
  def show
    @code = params[:code].to_s
    render layout: false
  end
end
