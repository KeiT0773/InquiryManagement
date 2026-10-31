# 開発用のサンプルの問い合わせ 8 件（データ設計書 7.2）。画面モック（mock/script.js）と同じ内容。
# 日付は投入した日を基準にした相対日付で、いつ投入しても期限切れの例が含まれる。
# 件名で既存かどうかを確かめるので、2 回実行しても重複しない。
# 表示順はリストごとに並べた順で 0 から振る。「対応中」はあえて優先度順になっていない
today = Time.zone.today

samples = {
  "open" => [
    { title: "ログインできない", customer_name: "山田 太郎", contact: "yamada@example.com", category: "bug",
      content: "パスワードを再設定してもログイン画面に戻される。", memo: nil, assignee: nil,
      received_on: today - 1, due_on: today + 1, priority: "high" },
    { title: "請求書の再発行について", customer_name: "佐藤 花子", contact: "03-1234-5678", category: "question",
      content: "先月分の請求書を紛失したため再発行してほしい。", memo: nil, assignee: "小林",
      received_on: today - 4, due_on: today - 1, priority: "medium" },
    { title: "CSV出力に項目を追加してほしい", customer_name: "鈴木 一郎", contact: "suzuki@example.com", category: "request",
      content: "問い合わせ一覧の CSV に受付日を含めてほしい。", memo: nil, assignee: nil,
      received_on: today, due_on: nil, priority: "low" }
  ],
  "working" => [
    { title: "プラン変更の手続き", customer_name: "高橋 美咲", contact: "takahashi@example.com", category: "question",
      content: "年契約から月契約に切り替えたい。", memo: "契約担当に確認中。", assignee: "小林",
      received_on: today - 3, due_on: today + 3, priority: "medium" },
    { title: "画面が真っ白になる", customer_name: "田中 健", contact: "tanaka@example.com", category: "bug",
      content: "Safari で一覧画面を開くと何も表示されない。", memo: "再現手順を開発チームに共有済み。", assignee: "中村",
      received_on: today - 2, due_on: today, priority: "high" },
    { title: "領収書の宛名を変更したい", customer_name: "小川 直子", contact: "ogawa@example.com", category: "question",
      content: "領収書の宛名を会社名に変更して再発行してほしい。", memo: "経理に確認中。", assignee: "中村",
      received_on: today - 2, due_on: today + 1, priority: "medium" }
  ],
  "closed" => [
    { title: "営業時間の確認", customer_name: "伊藤 さくら", contact: "090-0000-1111", category: "other",
      content: "電話窓口の営業時間を教えてほしい。", memo: "平日 9:00〜18:00 と回答。", assignee: "中村",
      received_on: today - 6, due_on: nil, priority: "low" },
    { title: "退会方法を知りたい", customer_name: "渡辺 誠", contact: "watanabe@example.com", category: "question",
      content: "アカウントの退会手順が分からない。", memo: "ヘルプページの URL を案内。", assignee: "小林",
      received_on: today - 5, due_on: today - 3, priority: "medium" }
  ]
}

samples.each do |list_id, inquiries|
  inquiries.each_with_index do |attributes, index|
    Inquiry.find_or_create_by!(title: attributes[:title]) do |inquiry|
      inquiry.assign_attributes(attributes.merge(list_id: list_id, display_order: index))
    end
  end
end
