# 問い合わせ（データ設計書 4.2）
class Inquiry < ApplicationRecord
  belongs_to :list, inverse_of: :inquiries

  # 列には英語の値をそのまま保存する（データ設計書 9.）。
  # validate: true で、一覧にない値は例外ではなく入力チェックのエラーにする
  enum :category, { question: "question", bug: "bug", request: "request", other: "other" },
       prefix: true, validate: true
  enum :priority, { high: "high", medium: "medium", low: "low" }, prefix: true, validate: true

  # 前後の空白（全角の空白を含む）を除き、空になったら NULL にする（データ要件書 2.2）。
  # Ruby の strip も MySQL の TRIM も全角の空白を除かないため、[[:space:]] で除く
  normalizes :title, :customer_name, :contact, :content, :memo, :assignee,
             with: ->(value) { value.gsub(/\A[[:space:]]+|[[:space:]]+\z/, "").presence }

  validates :title, presence: true, length: { maximum: 100 }
  validates :customer_name, presence: true, length: { maximum: 50 }
  validates :contact, length: { maximum: 100 }
  validates :content, presence: true, length: { maximum: 2000 }
  validates :memo, length: { maximum: 2000 }
  validates :assignee, length: { maximum: 50 }
  validates :received_on, presence: true
  validates :display_order, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # 受付日は登録時に日本時間の今日を入れる。DB の CURRENT_DATE は RDS では UTC になるため使わない（データ設計書 5.4）
  before_validation :set_received_on, on: :create

  private

  def set_received_on
    self.received_on ||= Time.zone.today
  end
end
