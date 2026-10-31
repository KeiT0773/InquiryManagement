# すべての環境で実行する（データ設計書 10.4）。何度実行しても同じ結果になるように書く。
#
# リストの 3 件はマイグレーションでも入れているが、ここでも入れる。
# DB が空のときの db:prepare・db:reset は、マイグレーションを実行せずに schema.rb を読み込むため、
# マイグレーションの INSERT が実行されない。そのあとに実行されるこのファイルで補う（データ設計書 7.1）。
List.upsert_all([
  { id: "open", name: "未対応", display_order: 0 },
  { id: "working", name: "対応中", display_order: 1 },
  { id: "closed", name: "完了", display_order: 2 }
])

# 環境ごとのデータ（開発用のサンプルなど）。本番用のファイルは置かないので、本番では何も入らない
environment_seeds = Rails.root.join("db/seeds/#{Rails.env}.rb")
load environment_seeds if environment_seeds.exist?
