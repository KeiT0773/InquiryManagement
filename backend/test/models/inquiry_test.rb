require "test_helper"

class InquiryTest < ActiveSupport::TestCase
  def build_inquiry(**attributes)
    Inquiry.new({ title: "件名", customer_name: "問い合わせ者", content: "内容", list: lists(:open), display_order: 2 }
                  .merge(attributes))
  end

  test "必須の項目だけで登録でき、種別・優先度は既定値になる" do
    inquiry = build_inquiry
    assert inquiry.save
    assert inquiry.reload.category_question?
    assert inquiry.priority_medium?
  end

  # --- 前後の空白と NULL（データ要件書 2.2） ---

  test "前後の空白（全角を含む）を取り除いて保存する" do
    inquiry = build_inquiry(title: " 　ログインできない　\n", assignee: "　小林 ")
    assert_equal "ログインできない", inquiry.title
    assert_equal "小林", inquiry.assignee
  end

  test "途中の空白と改行は残す" do
    inquiry = build_inquiry(content: "1 行目\n\n2 行目　です")
    assert_equal "1 行目\n\n2 行目　です", inquiry.content
  end

  test "任意項目は空白だけなら NULL にする" do
    inquiry = build_inquiry(contact: " ", memo: "　　", assignee: "")
    assert inquiry.save
    inquiry.reload
    assert_nil inquiry.contact
    assert_nil inquiry.memo
    assert_nil inquiry.assignee
  end

  test "必須の 3 項目が空白だけなら、すべて日本語のエラーになる" do
    inquiry = build_inquiry(title: "　", customer_name: " ", content: "")
    assert_not inquiry.valid?
    assert_equal [ "件名を入力してください", "問い合わせ者を入力してください", "問い合わせ内容を入力してください" ],
                 inquiry.errors.full_messages
  end

  # --- 文字数の上限（データ要件書 2.1） ---

  test "文字数の上限ちょうどは保存できる" do
    inquiry = build_inquiry(title: "あ" * 100, customer_name: "あ" * 50, contact: "a" * 100,
                            content: "あ" * 2000, memo: "あ" * 2000, assignee: "あ" * 50)
    assert inquiry.save
  end

  test "文字数の上限を超えるとエラーになる" do
    inquiry = build_inquiry(title: "あ" * 101, customer_name: "あ" * 51, contact: "a" * 101,
                            content: "あ" * 2001, memo: "あ" * 2001, assignee: "あ" * 51)
    assert_not inquiry.valid?
    assert_includes inquiry.errors.full_messages, "件名は100文字以内で入力してください"
    assert_equal %i[title customer_name contact content memo assignee], inquiry.errors.attribute_names
  end

  test "上限は前後の空白を除いた文字数で判定する" do
    assert build_inquiry(title: "　#{"あ" * 100}　").valid?
  end

  # --- 種別・優先度・所属リスト ---

  test "一覧にない種別・優先度は例外ではなくエラーになる" do
    inquiry = build_inquiry(category: "urgent", priority: "highest")
    assert_not inquiry.valid?
    assert_equal [ "種別は一覧にない値です", "優先度は一覧にない値です" ], inquiry.errors.full_messages
  end

  test "所属リストが無いとエラーになる" do
    inquiry = build_inquiry(list: nil)
    assert_not inquiry.valid?
    assert_includes inquiry.errors.full_messages, "所属リストを入力してください"
  end

  test "表示順は 0 以上の整数" do
    assert_not build_inquiry(display_order: -1).valid?
    assert_not build_inquiry(display_order: 1.5).valid?
    assert build_inquiry(display_order: 0).valid?
  end

  # --- 受付日（データ設計書 5.4） ---

  test "受付日は日本時間の今日になる（UTC ではまだ前日の時刻でも）" do
    travel_to Time.utc(2026, 10, 31, 16, 0, 0) do # 日本時間 11/1 1:00
      inquiry = build_inquiry
      inquiry.save!
      assert_equal Date.new(2026, 11, 1), inquiry.received_on
    end
  end

  test "受付日は更新しても変わらない" do
    inquiry = inquiries(:login)
    travel_to Time.zone.local(2026, 12, 1) do
      inquiry.update!(title: "ログインできない（再発）")
    end
    assert_equal Date.new(2026, 10, 30), inquiry.reload.received_on
  end

  # --- 表示順を振り直すトランザクション（データ設計書 6.2） ---

  test "ロックを待つ間に別のリストへ動かされていたら、読み直した list_id でやり直す" do
    inquiry = inquiries(:login)
    Inquiry.find(inquiry.id).update_columns(list_id: "working") # ほかのメンバーが動かした
    attempts = 0

    Inquiry.reorder_transaction do
      attempts += 1
      inquiry.lock_lists!
    end

    assert_equal 2, attempts
    assert_equal "working", inquiry.list_id
  end

  test "デッドロックで取り消されたら、最初からやり直す。続けて失敗したら例外を返す" do
    attempts = 0
    Inquiry.reorder_transaction do
      attempts += 1
      raise ActiveRecord::Deadlocked, "deadlock" if attempts == 1
    end
    assert_equal 2, attempts

    assert_raises(ActiveRecord::Deadlocked) do
      Inquiry.reorder_transaction(attempts: 3) { raise ActiveRecord::Deadlocked, "deadlock" }
    end
  end

  test "sort_by_priority は優先度 → 期限の近い順（未設定は後ろ）、同じものは元の順序を保つ" do
    rows = [ [ "a", "low", nil ], [ "b", "high", nil ], [ "c", "medium", "2026-11-05" ], [ "d", "high", "2026-11-01" ],
             [ "e", "medium", nil ], [ "f", "medium", "2026-11-05" ], [ "g", "high", nil ] ]
    inquiries = rows.map { |title, priority, due_on| Inquiry.new(title: title, priority: priority, due_on: due_on) }

    assert_equal %w[d b g c f e a], Inquiry.sort_by_priority(inquiries).map(&:title)
  end

  # --- DB の制約（モデルを通らない書き込みに対する最後の防壁。データ設計書 5.1） ---

  test "DB の CHECK 制約が、空白だけの必須項目と一覧にない値を拒否する" do
    inquiry = inquiries(:login)
    { title: " ", customer_name: "", content: "  ", category: "urgent", priority: "highest", display_order: -1 }
      .each do |column, value|
        assert_raises(ActiveRecord::StatementInvalid, "#{column} の制約") { inquiry.update_columns(column => value) }
      end
  end

  test "DB の外部キーが、存在しないリストへの所属を拒否する" do
    assert_raises(ActiveRecord::InvalidForeignKey) { inquiries(:login).update_columns(list_id: "unknown") }
  end
end
