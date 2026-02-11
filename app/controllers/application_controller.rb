class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  around_action :switch_database

  private

  def switch_database(&block)
    if request.get? || request.head?
      role = DatabaseLoadBalancer.instance.reading_role
      ApplicationRecord.connected_to(role: role) do
        yield
      end
      routing_duration = Thread.current[:redis_routing_duration]
      Rails.logger.info "Redis Routing Duration: #{(routing_duration * 1000).round(2)}ms" if routing_duration
    else
      # Write operations (POST, PUT, DELETE, PATCH) directly use primary
      yield
    end
  end

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes
end
