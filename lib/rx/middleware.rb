require "json"

module Rx
  class Middleware
    DEFAULT_OPTIONS = {
      cache: true,
      authorization: nil,
      liveness_path: "/liveness",
      readiness_path: "/readiness",
      deep_path: "/deep"
    }.freeze

    def initialize(app,
                   liveness:       [Rx::Check::FileSystemCheck.new],
                   readiness:      [Rx::Check::FileSystemCheck.new],
                   deep_critical:  [],
                   deep_secondary: [],
                   options:        {})
      @app = app
      @options = DEFAULT_OPTIONS.merge(options)
      @cache = cache_factory(@options)

      @liveness_checks = liveness
      @readiness_checks = readiness
      @deep_critical_checks = deep_critical
      @deep_secondary_checks = deep_secondary
    end

    def call(env)
      unless health_check_request?(path(env))
        return app.call(env)
      end

      case path(env)
      when @options[:liveness_path]
        liveness_response(check_to_component(liveness_checks))
      when @options[:readiness_path]
        readiness_response(check_to_component(readiness_checks))
      when @options[:deep_path]
        if !Rx::Util::HealthCheckAuthorization.new(env, @options[:authorization]).ok?
          deep_response_authorization_failed
        else
          @cache.cache("deep") do
            critical  = check_to_component(deep_critical_checks)
            secondary = check_to_component(deep_secondary_checks)

            deep_response(critical, secondary)
          end
        end
      end
    end

    private

    attr_reader :app, :liveness_checks, :readiness_checks, :deep_critical_checks,
                :deep_secondary_checks, :options

    def cache_factory(options)
      case options[:cache]
      when true
        Rx::Cache::LRUCache.new
      when "LRU"
        Rx::Cache::LRUCache.new
      when "MAP"
        Rx::Cache::MapCache.new
      else
        Rx::Cache::NoOpCache.new
      end
    end

    def health_check_request?(path)
      [@options[:liveness_path], @options[:readiness_path], @options[:deep_path]].include?(path)
    end

    def liveness_response(is_ok)
      [
        is_ok ? 200 : 500,
        {"content-type" => "application/json"},
        []
      ]
    end

    def path(env)
      env["PATH_INFO"] || env["REQUEST_PATH"] || env["REQUEST_URI"]
    end

    def liveness_response(components)
      status = components.all? { |x| x[x.keys.first][:alive] } ? 200 : 500
      status_string = status == 200 ? "ok" : "error"

      [
        status,
        {"content-type" => "application/json"},
        [JSON.dump({status: status_string, integrations: components})]
      ]
    end

    def readiness_response(components)
      status = components.all? { |x| x[x.keys.first][:alive] } ? 200 : 500
      status_string = status == 200 ? "ok" : "error"

      [
        status,
        {"content-type" => "application/json"},
        [JSON.dump({status: status_string, integrations: components})]
      ]
    end

    def deep_response_authorization_failed
      [
        403,
        {"content-type" => "application/json"},
        [JSON.dump({ message: "authorization failed" })]
      ]
    end

    def deep_response(critical, secondary)
      status_critical = critical.all? { |x| x[x.keys.first][:alive] } ? 200 : 500
      status_secondary = secondary.all? { |x| x[x.keys.first][:alive] } ? 200 : 500
      status_string = status_critical == 200 ? "ok" : "error"
      status_string = "degraded" if status_critical == 200 && status_secondary == 500

      [
        status_critical,
        {"content-type" => "application/json"},
        [JSON.dump(status: status_string, integrations: critical + secondary)]
      ]
    end

    def check_to_component(check)
      secondary_checks_names = deep_secondary_checks.to_a.map(&:name)

      Array(check)
        .map { |check| Rx::Concurrent::Future.execute { check.check } }
        .map(&:value)
        .map { |r| {r.name => { alive: r.ok? ? true : false, duration: r.timing, required: !secondary_checks_names.include?(r.name) } }}
    end
  end
end
