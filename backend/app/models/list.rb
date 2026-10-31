# リスト（ステータス）。未対応 / 対応中 / 完了 の 3 件で固定（データ設計書 4.1）
class List < ApplicationRecord
  # 新しい問い合わせを登録できるリスト（機能要件書 FR-01）
  REGISTER_LIST_ID = "open".freeze

  has_many :inquiries, -> { order(:display_order) }, dependent: :restrict_with_exception, inverse_of: :list

  scope :ordered, -> { order(:display_order) }
end
