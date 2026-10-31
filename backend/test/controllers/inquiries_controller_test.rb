require "test_helper"

# fixtures の初期状態
#   未対応：login（高・期限 11/01）→ invoice（中・期限なし）
#   対応中：plan（中・期限 11/03）
#   完了：なし
class InquiriesControllerTest < ActionDispatch::IntegrationTest
  # リストの末尾に問い合わせを追加する（並べ替えのテスト用）
  def add_inquiry(list_id, title, priority: "medium", due_on: nil)
    Inquiry.create!(title: title, customer_name: "問い合わせ者", content: "内容", priority: priority, due_on: due_on,
                    list_id: list_id, display_order: Inquiry.where(list_id: list_id).count)
  end

  def titles_in(list_id)
    Inquiry.where(list_id: list_id).in_display_order.pluck(:title)
  end

  def display_orders_in(list_id)
    Inquiry.where(list_id: list_id).in_display_order.pluck(:display_order)
  end

  def json_request(method, path, body)
    send(method, path, params: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  def assert_problem(status, detail)
    assert_response status
    assert_equal "application/problem+json", response.media_type
    assert_equal detail, response.parsed_body["detail"]
  end

  # ---------- GET /api/inquiries ----------

  test "一覧はリストの並び順、リスト内の表示順で返す" do
    get "/api/inquiries"

    assert_response :ok
    assert_equal [ [ "open", 0 ], [ "open", 1 ], [ "working", 0 ] ],
                 response.parsed_body.map { |inquiry| [ inquiry["listId"], inquiry["displayOrder"] ] }
  end

  test "listId で絞り込める。存在しない listId なら空の配列" do
    get "/api/inquiries", params: { listId: "working" }
    assert_equal [ "プラン変更の手続き" ], response.parsed_body.pluck("title")

    get "/api/inquiries", params: { listId: "unknown" }
    assert_response :ok
    assert_equal [], response.parsed_body
  end

  # ---------- GET /api/inquiries/{id} ----------

  test "1 件を 4.2 の形式で返す。値が無い項目も null で含める" do
    inquiry = inquiries(:login)
    get "/api/inquiries/#{inquiry.id}"

    assert_response :ok
    assert_equal({
      "id" => inquiry.id, "title" => "ログインできない", "customerName" => "山田 太郎", "contact" => "yamada@example.com",
      "category" => "bug", "content" => "パスワードを再設定してもログイン画面に戻される。", "memo" => nil, "assignee" => nil,
      "receivedOn" => "2026-10-30", "dueOn" => "2026-11-01", "priority" => "high", "listId" => "open", "displayOrder" => 0,
      "createdAt" => inquiry.created_at.utc.iso8601(3), "updatedAt" => inquiry.updated_at.utc.iso8601(3)
    }, response.parsed_body)
    assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\z/, response.parsed_body["createdAt"])
  end

  test "存在しない id・数値でない id は 404" do
    get "/api/inquiries/999999"
    assert_problem :not_found, "問い合わせが見つかりません: id=999999"
    assert_equal "/api/inquiries/999999", response.parsed_body["instance"]

    get "/api/inquiries/abc"
    assert_problem :not_found, "問い合わせが見つかりません: id=abc"

    get "/api/inquiries/#{inquiries(:login).id}abc"
    assert_response :not_found
  end

  # ---------- POST /api/inquiries ----------

  test "登録すると 201 と Location を返し、未対応に日本時間の今日の受付日で入る" do
    travel_to Time.utc(2026, 10, 31, 16, 0, 0) do # 日本時間 11/1 1:00
      json_request :post, "/api/inquiries",
                   { title: "　請求書が届かない ", customerName: "木村 翔", content: "今月分が届かない。", category: "question" }
    end

    assert_response :created
    body = response.parsed_body
    assert_equal "/api/inquiries/#{body["id"]}", response.headers["Location"]
    assert_equal "請求書が届かない", body["title"]
    assert_equal "2026-11-01", body["receivedOn"]
    assert_equal "open", body["listId"]
    assert_equal "medium", body["priority"]
    assert_nil body["contact"]
  end

  test "登録では listId・連絡先・期限・受付日などを受け取らない。種別・優先度は null なら既定値" do
    json_request :post, "/api/inquiries",
                 { title: "件名", customerName: "問い合わせ者", content: "内容", category: nil, priority: nil,
                   listId: "closed", contact: "a@example.com", memo: "メモ", assignee: "小林", dueOn: "2026-12-01",
                   receivedOn: "2000-01-01", displayOrder: 99 }

    assert_response :created
    body = response.parsed_body
    assert_equal [ "open", "question", "medium", nil, nil, nil, nil ],
                 body.values_at("listId", "category", "priority", "contact", "memo", "assignee", "dueOn")
    assert_equal Time.zone.today.iso8601, body["receivedOn"]
  end

  test "登録後に未対応を優先度順に並べ直し、新しい問い合わせは同じまとまりの末尾に入る" do
    add_inquiry("open", "低い問い合わせ", priority: "low")
    add_inquiry("open", "高い・期限なし", priority: "high")
    # この時点では規則どおりでない：高(期限あり) → 中 → 低 → 高(期限なし)

    json_request :post, "/api/inquiries", { title: "新しい高", customerName: "問い合わせ者", content: "内容", priority: "high" }

    assert_response :created
    assert_equal [ "ログインできない", "高い・期限なし", "新しい高", "請求書の再発行について", "低い問い合わせ" ], titles_in("open")
    assert_equal [ 0, 1, 2, 3, 4 ], display_orders_in("open")
    assert_equal 2, response.parsed_body["displayOrder"]
  end

  test "必須の 3 項目が空なら 422 で、空の項目すべてを errors に含める" do
    json_request :post, "/api/inquiries", { title: "　", customerName: "", category: "bug" }

    assert_problem :unprocessable_content, "件名を入力してください、問い合わせ者を入力してください、問い合わせ内容を入力してください"
    assert_equal [
      { "field" => "title", "message" => "件名を入力してください" },
      { "field" => "customerName", "message" => "問い合わせ者を入力してください" },
      { "field" => "content", "message" => "問い合わせ内容を入力してください" }
    ], response.parsed_body["errors"]
    assert_equal 2, Inquiry.where(list_id: "open").count
  end

  test "一覧にない種別・上限を超える件名・オブジェクトの値は 422" do
    json_request :post, "/api/inquiries",
                 { title: "あ" * 101, customerName: { name: "x" }, content: "内容", category: "urgent" }

    assert_response :unprocessable_content
    assert_equal [
      { "field" => "customerName", "message" => "問い合わせ者は不正な値です" }
    ], response.parsed_body["errors"]

    json_request :post, "/api/inquiries", { title: "あ" * 101, customerName: "問い合わせ者", content: "内容", category: "urgent" }
    assert_equal %w[category title], response.parsed_body["errors"].pluck("field").sort
    assert_includes response.parsed_body["detail"], "件名は100文字以内で入力してください"
  end

  test "JSON として読めない body は 400" do
    post "/api/inquiries", params: "{ title: ", headers: { "Content-Type" => "application/json" }

    assert_problem :bad_request, "要求の本文を JSON として読めません"
  end

  # ---------- PATCH /api/inquiries/{id} ----------

  test "送った項目だけを変え、ほかの項目はそのまま" do
    inquiry = inquiries(:invoice)
    json_request :patch, "/api/inquiries/#{inquiry.id}", { assignee: " 中村 ", memo: "再発行の手配中" }

    assert_response :ok
    body = response.parsed_body
    assert_equal [ "中村", "再発行の手配中", "請求書の再発行について", "佐藤 花子", "medium" ],
                 body.values_at("assignee", "memo", "title", "customerName", "priority")
    assert_equal "中村", inquiry.reload.assignee
  end

  test "任意項目は null・空白だけで値を消せる。期限は null で解除できる" do
    inquiry = inquiries(:login)
    json_request :patch, "/api/inquiries/#{inquiry.id}", { contact: nil, assignee: "　", dueOn: nil }

    assert_response :ok
    inquiry.reload
    assert_nil inquiry.contact
    assert_nil inquiry.assignee
    assert_nil inquiry.due_on
  end

  test "期限を変えても並べ直さない" do
    inquiry = inquiries(:invoice)
    json_request :patch, "/api/inquiries/#{inquiry.id}", { dueOn: "2026-10-01" }

    assert_response :ok
    assert_equal "2026-10-01", response.parsed_body["dueOn"]
    assert_equal [ "ログインできない", "請求書の再発行について" ], titles_in("open")
  end

  test "優先度が変わったときだけ、変更後の優先度のまとまりの末尾へ並べ直す" do
    add_inquiry("open", "低い問い合わせ", priority: "low")
    json_request :patch, "/api/inquiries/#{inquiries(:login).id}", { priority: "low" }

    assert_response :ok
    # 低のまとまりの中では、期限のある login が期限なしより上
    assert_equal [ "請求書の再発行について", "ログインできない", "低い問い合わせ" ], titles_in("open")
    assert_equal 1, response.parsed_body["displayOrder"]

    add_inquiry("open", "中・期限なし")
    json_request :patch, "/api/inquiries/#{inquiries(:login).id}", { priority: "medium", dueOn: nil }
    assert_equal [ "請求書の再発行について", "中・期限なし", "ログインできない", "低い問い合わせ" ], titles_in("open")
  end

  test "優先度が同じ値なら並べ直さない" do
    add_inquiry("open", "高い・期限なし", priority: "high")
    inquiry = inquiries(:invoice)
    json_request :patch, "/api/inquiries/#{inquiry.id}", { priority: "medium" }

    assert_response :ok
    assert_equal [ "ログインできない", "請求書の再発行について", "高い・期限なし" ], titles_in("open")
  end

  test "必須項目を空・null にすると 422 で、何も保存しない" do
    inquiry = inquiries(:login)
    json_request :patch, "/api/inquiries/#{inquiry.id}", { title: nil, assignee: "小林" }

    assert_problem :unprocessable_content, "件名を入力してください"
    assert_equal [ { "field" => "title", "message" => "件名を入力してください" } ], response.parsed_body["errors"]
    assert_nil inquiry.reload.assignee
  end

  test "期限が日付として読めなければ 422" do
    inquiry = inquiries(:login)
    [ "2026-02-30", "2026/11/01", "2026-1-1", "明日", 20261101 ].each do |value|
      json_request :patch, "/api/inquiries/#{inquiry.id}", { dueOn: value }

      assert_problem :unprocessable_content, "対応期限は YYYY-MM-DD の形式で指定してください"
      assert_equal "dueOn", response.parsed_body["errors"].first["field"]
    end
    assert_equal Date.new(2026, 11, 1), inquiry.reload.due_on
  end

  test "変更できる項目が 1 つも無い body は 422。listId や receivedOn は無視する" do
    inquiry = inquiries(:login)
    [ {}, { listId: "closed", displayOrder: 3, receivedOn: "2000-01-01" } ].each do |body|
      json_request :patch, "/api/inquiries/#{inquiry.id}", body
      assert_problem :unprocessable_content, "変更する項目を指定してください"
    end
    assert_equal [ "open", 0 ], [ inquiry.reload.list_id, inquiry.display_order ]
  end

  test "編集する問い合わせが無ければ 404" do
    json_request :patch, "/api/inquiries/999999", { title: "件名" }
    assert_response :not_found
  end

  test "PUT での編集は受け付けない" do
    json_request :put, "/api/inquiries/#{inquiries(:login).id}", { title: "件名" }
    assert_response :not_found
  end

  # ---------- PUT /api/inquiries/{id}/position ----------

  test "別のリストの指定した位置へ移し、移動元と移動先の両方を振り直す。優先度順には並べ直さない" do
    add_inquiry("working", "対応中の 2 件目", priority: "low")
    inquiry = inquiries(:login)
    json_request :put, "/api/inquiries/#{inquiry.id}/position", { listId: "working", displayOrder: 1 }

    assert_response :ok
    assert_equal [ "working", 1 ], response.parsed_body.values_at("listId", "displayOrder")
    assert_equal [ "請求書の再発行について" ], titles_in("open")
    assert_equal [ 0 ], display_orders_in("open")
    assert_equal [ "プラン変更の手続き", "ログインできない", "対応中の 2 件目" ], titles_in("working")
    assert_equal [ 0, 1, 2 ], display_orders_in("working")
  end

  test "displayOrder を省略・null・件数以上にすると移動先の末尾に置く" do
    [ {}, { displayOrder: nil }, { displayOrder: 100 } ].each_with_index do |extra, index|
      inquiry = add_inquiry("open", "移す #{index}")
      json_request :put, "/api/inquiries/#{inquiry.id}/position", { listId: "closed" }.merge(extra)

      assert_response :ok
      assert_equal index, response.parsed_body["displayOrder"]
    end
    assert_equal [ "移す 0", "移す 1", "移す 2" ], titles_in("closed")
  end

  test "同じリスト内の並べ替えでは、位置は自分を除いた並びの何番目か" do
    add_inquiry("open", "3 件目")
    json_request :put, "/api/inquiries/#{inquiries(:login).id}/position", { listId: "open", displayOrder: 2 }

    assert_response :ok
    assert_equal [ "請求書の再発行について", "3 件目", "ログインできない" ], titles_in("open")

    json_request :put, "/api/inquiries/#{inquiries(:login).id}/position", { listId: "open", displayOrder: 0 }
    assert_equal [ "ログインできない", "請求書の再発行について", "3 件目" ], titles_in("open")
    assert_equal [ 0, 1, 2 ], display_orders_in("open")
  end

  test "完了から未対応へ戻せる。listId の大文字小文字が違っても DB の id で保存する" do
    inquiry = inquiries(:plan)
    json_request :put, "/api/inquiries/#{inquiry.id}/position", { listId: "closed" }
    json_request :put, "/api/inquiries/#{inquiry.id}/position", { listId: "OPEN", displayOrder: 0 }

    assert_response :ok
    assert_equal "open", inquiry.reload.list_id
    assert_equal [ "プラン変更の手続き", "ログインできない", "請求書の再発行について" ], titles_in("open")
  end

  test "存在しないリストへの移動は 422" do
    json_request :put, "/api/inquiries/#{inquiries(:login).id}/position", { listId: "archived" }

    assert_problem :unprocessable_content, "リストが見つかりません: listId=archived"
    assert_equal "open", inquiries(:login).reload.list_id
  end

  test "listId が無い、displayOrder が 0 以上の整数でなければ 422" do
    inquiry = inquiries(:login)
    json_request :put, "/api/inquiries/#{inquiry.id}/position", { displayOrder: -1 }

    assert_problem :unprocessable_content, "移動先のリストを指定してください、表示順は0以上の整数で指定してください"
    assert_equal %w[listId displayOrder], response.parsed_body["errors"].pluck("field")

    [ 1.5, "1", true ].each do |value|
      json_request :put, "/api/inquiries/#{inquiry.id}/position", { listId: "working", displayOrder: value }
      assert_problem :unprocessable_content, "表示順は0以上の整数で指定してください"
    end
  end

  test "動かす問い合わせが無ければ 404" do
    json_request :put, "/api/inquiries/999999/position", { listId: "open" }
    assert_response :not_found
  end

  # ---------- POST /api/inquiries/sort ----------

  test "全リストを優先度 → 期限の近い順（未設定は後ろ）に並べ直し、同じものは今の順序を保つ" do
    add_inquiry("working", "中・期限なし A")
    add_inquiry("working", "高・期限 11/05", priority: "high", due_on: "2026-11-05")
    add_inquiry("working", "中・期限なし B")
    add_inquiry("working", "高・期限 11/02", priority: "high", due_on: "2026-11-02")
    add_inquiry("working", "中・期限 10/20（超過）", due_on: "2026-10-20")
    add_inquiry("closed", "低", priority: "low")
    add_inquiry("closed", "高", priority: "high")

    post "/api/inquiries/sort"

    assert_response :no_content
    assert_equal [ "高・期限 11/02", "高・期限 11/05", "中・期限 10/20（超過）", "プラン変更の手続き", "中・期限なし A", "中・期限なし B" ],
                 titles_in("working")
    assert_equal (0..5).to_a, display_orders_in("working")
    assert_equal [ "高", "低" ], titles_in("closed")
    assert_equal [ "ログインできない", "請求書の再発行について" ], titles_in("open")
  end

  test "並べ替えは何回呼んでも同じ結果で、位置が変わらない問い合わせは更新しない" do
    add_inquiry("open", "中・期限なし")
    post "/api/inquiries/sort"
    before = Inquiry.order(:id).pluck(:id, :list_id, :display_order, :updated_at)

    travel 1.minute do
      post "/api/inquiries/sort"
    end

    assert_response :no_content
    assert_equal before, Inquiry.order(:id).pluck(:id, :list_id, :display_order, :updated_at)
  end

  # ---------- DELETE /api/inquiries/{id} ----------

  test "削除すると 204 を返し、そのリストの残りの表示順を詰める" do
    add_inquiry("open", "3 件目", priority: "high")
    delete "/api/inquiries/#{inquiries(:login).id}"

    assert_response :no_content
    assert_not Inquiry.exists?(inquiries(:login).id)
    assert_equal [ "請求書の再発行について", "3 件目" ], titles_in("open")
    assert_equal [ 0, 1 ], display_orders_in("open")
  end

  test "削除済みの問い合わせを削除すると 404" do
    id = inquiries(:login).id
    delete "/api/inquiries/#{id}"
    delete "/api/inquiries/#{id}"

    assert_problem :not_found, "問い合わせが見つかりません: id=#{id}"
  end
end
