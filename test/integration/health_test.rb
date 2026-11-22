require "test_helper"

class HealthTest < ActionDispatch::IntegrationTest
  test "health endpoint reports the Rails API is available" do
    get "/up"

    assert_response :success
  end
end
