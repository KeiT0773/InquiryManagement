# 問い合わせ（データ設計書 4.2・5.）
class CreateInquiries < ActiveRecord::Migration[8.1]
  def change
    create_table :inquiries, comment: "問い合わせ。利用者が登録する問い合わせ 1 件" do |t|
      t.string :title, limit: 100, null: false, comment: "件名"
      t.string :customer_name, limit: 50, null: false, comment: "問い合わせ者の名前"
      t.string :contact, limit: 100, comment: "メールアドレスまたは電話番号。形式は検査しない"
      t.string :category, limit: 10, null: false, default: "question", comment: "種別。question / bug / request / other"
      t.string :content, limit: 2000, null: false, comment: "問い合わせ内容"
      t.string :memo, limit: 2000, comment: "対応メモ"
      t.string :assignee, limit: 50, comment: "対応者の名前。NULL は未割当"
      t.date :received_on, null: false, comment: "受付日。登録時に日本時間の今日"
      t.date :due_on, comment: "対応期限"
      t.string :priority, limit: 6, null: false, default: "medium", comment: "優先度。high / medium / low"
      t.string :list_id, limit: 10, null: false, comment: "所属リスト（lists.id）"
      t.integer :display_order, null: false, comment: "同じリスト内での表示順。0 から始まる通し番号"
      t.timestamps

      # 外部キーの索引も兼ねる（データ設計書 5.1）
      t.index [ :list_id, :display_order ], name: "ix_inquiries_list_display_order"

      # MySQL の TRIM は半角の空白だけを除く。全角の空白はモデルで除く（データ設計書 5.1）
      t.check_constraint "CHAR_LENGTH(TRIM(title)) > 0", name: "ck_inquiries_title"
      t.check_constraint "CHAR_LENGTH(TRIM(customer_name)) > 0", name: "ck_inquiries_customer_name"
      t.check_constraint "CHAR_LENGTH(TRIM(content)) > 0", name: "ck_inquiries_content"
      t.check_constraint "category IN ('question', 'bug', 'request', 'other')", name: "ck_inquiries_category"
      t.check_constraint "priority IN ('high', 'medium', 'low')", name: "ck_inquiries_priority"
      t.check_constraint "display_order >= 0", name: "ck_inquiries_display_order"
    end

    add_foreign_key :inquiries, :lists, name: "fk_inquiries_list", on_update: :cascade, on_delete: :restrict
  end
end
