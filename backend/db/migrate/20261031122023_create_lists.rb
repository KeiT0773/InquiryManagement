# リスト（ステータス）。未対応 / 対応中 / 完了 の 3 件で固定（データ設計書 4.1）
class CreateLists < ActiveRecord::Migration[8.1]
  def change
    create_table :lists, id: :string, limit: 10, comment: "リスト（ステータス）。未対応 / 対応中 / 完了 の 3 件で固定" do |t|
      t.string :name, limit: 20, null: false, comment: "画面に表示するリストの名称"
      t.integer :display_order, limit: 2, null: false, comment: "ボード上での並び順。左から 0, 1, 2"
    end
  end
end
