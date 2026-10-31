require "test_helper"

# コントローラーに届く前の失敗も Problem Details で返す（lib/problem_details_exceptions_app.rb）
class ProblemDetailsTest < ActionDispatch::IntegrationTest
  # テスト環境は Rails の詳しいエラー画面を先に出すため、本番と同じく出さないようにする
  setup do
    @env_config = Rails.application.env_config.slice("action_dispatch.show_detailed_exceptions")
    Rails.application.env_config["action_dispatch.show_detailed_exceptions"] = false
  end

  teardown do
    Rails.application.env_config.merge!(@env_config)
  end

  test "存在しない URL は 404" do
    get "/api/unknown?x=1"

    assert_response :not_found
    assert_equal "application/problem+json", response.media_type
    assert_equal({ "title" => "Not Found", "status" => 404, "detail" => "指定された URL はありません",
                   "instance" => "/api/unknown" }, response.parsed_body)
  end

  test "UTF-8 として読めない文字を含む body は 400" do
    post "/api/inquiries", params: "{\"title\":\"\x8Am\x94F\"}".b, headers: { "Content-Type" => "application/json" }

    assert_response :bad_request
    assert_equal "application/problem+json", response.media_type
    assert_equal "要求を読めません", response.parsed_body["detail"]
  end
end
