require "test_helper"

class MiddlewareTest < Minitest::Test
  def setup
    @app = -> (env) { [200, {}, ["response"]] }
    @middleware = Rx::Middleware.new(@app)
  end

  def test_it_responds_to_liveness_requests
    status, headers, body = @middleware.call("PATH_INFO" => "/liveness")

    assert_equal 200, status
    assert_equal({"content-type" => "application/json"}, headers)
    assert_equal 1, body[0].scan(/ok/).size
  end

  def test_liveness_fails_if_file_system_check_fails
    fs_check = Minitest::Mock.new
    fs_check.expect :check, Rx::Check::Result.new("fs", false, 100, "err")
    @middleware.instance_variable_set(:@liveness_checks, [fs_check])

    status, headers, body = @middleware.call("PATH_INFO" => "/liveness")

    assert_equal({"content-type" => "application/json"}, headers)
    assert_equal 500, status
    assert_equal 1, body[0].scan(/error/).size

  end

  def test_it_responds_to_readiness_requests
    status, headers, body = @middleware.call("PATH_INFO" => "/readiness")

    assert_equal 200, status
    assert_equal({"content-type" => "application/json"}, headers)
    assert_equal 1, body[0].scan(/ok/).size

  end

  def test_readiness_fails_if_any_one_check_fails
    check1 = Minitest::Mock.new
    check2 = Minitest::Mock.new

    check1.expect :check, Rx::Check::Result.new("1", true, 100, "ok")
    check2.expect :check, Rx::Check::Result.new("2", false, 100, "err")
    @middleware.instance_variable_set(:@readiness_checks, [check1, check2])

    status, headers, body = @middleware.call("PATH_INFO" => "/readiness")

    assert_equal 500, status
    assert_equal({"content-type" => "application/json"}, headers)
    assert_equal 1, body[0].scan(/error/).size
  end

  def test_it_responds_to_deep_requests
    status, headers, body = @middleware.call("PATH_INFO" => "/deep")

    assert_equal({"content-type" => "application/json"}, headers)
    assert_equal 1, body[0].scan(/ok/).size
  end

  def test_deep_check_fails_if_default_authorization_fails
    middleware = Rx::Middleware.new(@app, options: { authorization: "123"})

    status, _, _ = middleware.call({"PATH_INFO" => "/deep", "HTTP_AUTHORIZATION" => "12"})
    assert_equal 403, status
  end

  def test_deep_check_fails_if_custom_authorization_fails
    middleware = Rx::Middleware.new(@app, options: { authorization: -> (env) { false }})

    status, _, _ = middleware.call({"PATH_INFO" => "/deep"})
    assert_equal 403, status
  end

  def test_deep_check_fails_if_any_critical_fails
    failing_check = Minitest::Mock.new
    failing_check.expect :check, Rx::Check::Result.new("fail", false, 100, "err")
    @middleware.instance_variable_get(:@deep_critical_checks) << failing_check

    status, headers, body = @middleware.call("PATH_INFO" => "/deep")

    assert_equal 500, status
    assert_equal({"content-type" => "application/json"}, headers)
    assert_equal 1, body[0].scan(/error/).size

  end

  def test_deep_check_succeeds_even_if_a_secondary_fails
    failing_check = Minitest::Mock.new
    failing_check.expect :name, "secondary check"
    failing_check.expect :name, "secondary check"

    failing_check.expect :check, Rx::Check::Result.new("fail", false, 100, "err")
    @middleware.instance_variable_get(:@deep_secondary_checks) << failing_check

    status, headers, body = @middleware.call("PATH_INFO" => "/deep")

    assert_equal 200, status
    assert_equal({"content-type" => "application/json"}, headers)
    assert_equal 1, body[0].scan(/degraded/).size

  end

  def test_it_ignores_non_health_check_requests
    _, _, body = @middleware.call("PATH_INFO" => "/")
    assert_equal ["response"], body
  end

  def test_lru_cache_is_default
    middleware = Rx::Middleware.new(@app, options: { cache: true })
    assert_equal Rx::Cache::LRUCache, middleware.instance_variable_get(:@cache).class
  end

  def test_it_allows_selection_of_lru_cache
    middleware = Rx::Middleware.new(@app, options: { cache: "LRU" })
    assert_equal Rx::Cache::LRUCache, middleware.instance_variable_get(:@cache).class
  end

  def test_it_allows_selection_of_map_cache
    middleware = Rx::Middleware.new(@app, options: { cache: "MAP" })
    assert_equal Rx::Cache::MapCache, middleware.instance_variable_get(:@cache).class
  end

  def test_if_cache_option_is_false_no_caching_happens
    middleware = Rx::Middleware.new(@app, options: { cache: false }, deep_critical: [Rx::Check::FileSystemCheck.new])

    body1 = JSON.parse(middleware.call("PATH_INFO" => "/deep")[2].first)
    body2 = JSON.parse(middleware.call("PATH_INFO" => "/deep")[2].first)

    body1["integrations"]
      .zip(body2["integrations"])
      .each { |(a, b)| a["duration"] != b["duration"] }
  end

  def test_it_reads_path_info_from_request_uri
    status, _, body = @middleware.call("REQUEST_URI" => "/liveness")
    assert_equal 200, status

    assert_equal 1, body[0].scan(/status/).size
  end

  def test_it_reads_path_info_from_request_path
    status, _, body = @middleware.call("REQUEST_PATH" => "/liveness")
    assert_equal 200, status
    assert_equal 1, body[0].scan(/status/).size
  end

  def test_the_liveness_url_is_configurable
    middleware = Rx::Middleware.new(@app, options: { liveness_path: "/custom" })
    status, _, body = middleware.call("PATH_INFO" => "/custom")

    assert_equal 200, status
    assert_equal 1, body[0].scan(/status/).size
  end

  def test_the_readiness_url_is_configurable
    middleware = Rx::Middleware.new(@app, options: { readiness_path: "/custom" })
    status, _, body = middleware.call("PATH_INFO" => "/custom")

    assert_equal 200, status
    assert_equal 1, body[0].scan(/status/).size

  end

  def test_the_deep_url_is_configurable
    middleware = Rx::Middleware.new(@app, options: { deep_path: "/custom" })
    status, _, body = middleware.call("PATH_INFO" => "/custom")

    assert_equal 1, body[0].scan(/status/).size
  end
end
