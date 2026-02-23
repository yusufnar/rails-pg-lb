require 'json'
require 'singleton'

# Mock Redis and Rails for testing
module Redis
  class BaseConnectionError < StandardError; end
end

class MockRedis
  def initialize(should_fail = false)
    @should_fail = should_fail
    @data = {
      "db_status:replica_1" => { healthy: true }.to_json,
      "db_status:replica_2" => { healthy: false }.to_json
    }
  end

  def get(key)
    raise Redis::BaseConnectionError, "Connection refused" if @should_fail
    @data[key]
  end
end

class MockLogger
  def error(msg); puts "ERROR: #{msg}"; end
  def info(msg); puts "INFO: #{msg}"; end
end

class Rails
  def self.logger; @logger ||= MockLogger.new; end
end

# Fake DatabaseLoadBalancer logic
class TestLoadBalancer
  def initialize(redis)
    @redis = redis
    @replica_roles = [:replica_1, :replica_2]
  end

  def reading_role
    healthy_roles = []

    begin
      @replica_roles.each do |role|
        status_json = @redis.get("db_status:#{role}")
        if status_json
          status = JSON.parse(status_json)
          healthy_roles << role if status["healthy"]
        end
      end
    rescue Redis::BaseConnectionError => e
      Rails.logger.error "DatabaseLoadBalancer: Redis is down (#{e.message}). Falling back to all replicas."
      healthy_roles = @replica_roles
    end

    healthy_roles
  end
end

puts "--- Test Case 1: Redis is UP ---"
lb_up = TestLoadBalancer.new(MockRedis.new(false))
healthy_up = lb_up.reading_role
puts "Healthy roles: #{healthy_up}"
unless healthy_up == [:replica_1]
  puts "FAILED: Expected only replica_1 to be healthy"
  exit 1
end

puts "\n--- Test Case 2: Redis is DOWN ---"
lb_down = TestLoadBalancer.new(MockRedis.new(true))
healthy_down = lb_down.reading_role
puts "Healthy roles: #{healthy_down}"
unless healthy_down == [:replica_1, :replica_2]
  puts "FAILED: Expected all replicas to be healthy as fallback"
  exit 1
end

puts "\nVerification SUCCESS"
