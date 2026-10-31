# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_31_122057) do
  create_table "inquiries", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "問い合わせ。利用者が登録する問い合わせ 1 件", force: :cascade do |t|
    t.string "title", limit: 100, null: false, comment: "件名"
    t.string "customer_name", limit: 50, null: false, comment: "問い合わせ者の名前"
    t.string "contact", limit: 100, comment: "メールアドレスまたは電話番号。形式は検査しない"
    t.string "category", limit: 10, default: "question", null: false, comment: "種別。question / bug / request / other"
    t.string "content", limit: 2000, null: false, comment: "問い合わせ内容"
    t.string "memo", limit: 2000, comment: "対応メモ"
    t.string "assignee", limit: 50, comment: "対応者の名前。NULL は未割当"
    t.date "received_on", null: false, comment: "受付日。登録時に日本時間の今日"
    t.date "due_on", comment: "対応期限"
    t.string "priority", limit: 6, default: "medium", null: false, comment: "優先度。high / medium / low"
    t.string "list_id", limit: 10, null: false, comment: "所属リスト（lists.id）"
    t.integer "display_order", null: false, comment: "同じリスト内での表示順。0 から始まる通し番号"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["list_id", "display_order"], name: "ix_inquiries_list_display_order"
    t.check_constraint "`category` in (_utf8mb4'question',_utf8mb4'bug',_utf8mb4'request',_utf8mb4'other')", name: "ck_inquiries_category"
    t.check_constraint "`display_order` >= 0", name: "ck_inquiries_display_order"
    t.check_constraint "`priority` in (_utf8mb4'high',_utf8mb4'medium',_utf8mb4'low')", name: "ck_inquiries_priority"
    t.check_constraint "char_length(trim(`content`)) > 0", name: "ck_inquiries_content"
    t.check_constraint "char_length(trim(`customer_name`)) > 0", name: "ck_inquiries_customer_name"
    t.check_constraint "char_length(trim(`title`)) > 0", name: "ck_inquiries_title"
  end

  create_table "lists", id: { type: :string, limit: 10 }, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "リスト（ステータス）。未対応 / 対応中 / 完了 の 3 件で固定", force: :cascade do |t|
    t.string "name", limit: 20, null: false, comment: "画面に表示するリストの名称"
    t.integer "display_order", limit: 2, null: false, comment: "ボード上での並び順。左から 0, 1, 2"
  end

  add_foreign_key "inquiries", "lists", name: "fk_inquiries_list", on_update: :cascade
end
