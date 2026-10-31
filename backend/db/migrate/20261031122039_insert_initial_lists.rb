# リストの初期データ 3 件（データ設計書 7.1・10.2）。
# 後でモデルを変えても動くように、モデルのクラスは使わず SQL で入れる。
class InsertInitialLists < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      INSERT INTO lists (id, name, display_order) VALUES
        ('open',    '未対応', 0),
        ('working', '対応中', 1),
        ('closed',  '完了',   2)
    SQL
  end

  def down
    execute "DELETE FROM lists WHERE id IN ('open', 'working', 'closed')"
  end
end
