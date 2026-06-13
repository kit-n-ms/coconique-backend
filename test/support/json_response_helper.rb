module JsonResponseHelper
  def json_body
    JSON.parse(response.body)
  rescue JSON::ParserError
    {}
  end

  def assert_json_ok!
    assert_response :success
    assert_equal true, json_body["ok"]
  end
end
