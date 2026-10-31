require "test_helper"

class ListsControllerTest < ActionDispatch::IntegrationTest
  test "GET /api/lists はボードの並び順で 3 件を返す" do
    get "/api/lists"

    assert_response :ok
    assert_equal [
      { "id" => "open", "name" => "未対応", "displayOrder" => 0 },
      { "id" => "working", "name" => "対応中", "displayOrder" => 1 },
      { "id" => "closed", "name" => "完了", "displayOrder" => 2 }
    ], response.parsed_body
  end

  test "DB に接続できないなどのときは 500 を日本語の Problem Details で返す" do
    original = List.method(:ordered)
    List.define_singleton_method(:ordered) { raise ActiveRecord::ConnectionNotEstablished, "connection refused" }
    begin
      get "/api/lists"
    ensure
      List.define_singleton_method(:ordered, original)
    end

    assert_response :internal_server_error
    assert_equal "application/problem+json", response.media_type
    assert_equal({ "title" => "Internal Server Error", "status" => 500, "detail" => "サーバーでエラーが発生しました",
                   "instance" => "/api/lists" }, response.parsed_body)
  end
end
