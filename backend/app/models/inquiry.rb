# 問い合わせ（データ設計書 4.2）
class Inquiry < ApplicationRecord
  # 優先度順の並べ替えでの順位（小さいほど上。機能要件書 3.1）
  PRIORITY_RANK = { "high" => 0, "medium" => 1, "low" => 2 }.freeze

  belongs_to :list, inverse_of: :inquiries

  # 列には英語の値をそのまま保存する（データ設計書 9.）。
  # validate: true で、一覧にない値は例外ではなく入力チェックのエラーにする
  enum :category, { question: "question", bug: "bug", request: "request", other: "other" },
       prefix: true, validate: true
  enum :priority, { high: "high", medium: "medium", low: "low" }, prefix: true, validate: true

  # 前後の空白（全角の空白を含む）を除き、空になったら NULL にする（データ要件書 2.2）。
  # Ruby の strip も MySQL の TRIM も全角の空白を除かないため、[[:space:]] で除く。
  # JSON で数値などが送られても落ちないよう、文字列にしてから扱う
  normalizes :title, :customer_name, :contact, :content, :memo, :assignee,
             with: ->(value) { value.to_s.gsub(/\A[[:space:]]+|[[:space:]]+\z/, "").presence }

  validates :title, presence: true, length: { maximum: 100 }
  validates :customer_name, presence: true, length: { maximum: 50 }
  validates :contact, length: { maximum: 100 }
  validates :content, presence: true, length: { maximum: 2000 }
  validates :memo, length: { maximum: 2000 }
  validates :assignee, length: { maximum: 50 }
  validates :received_on, presence: true
  validates :display_order, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :due_on_must_be_date

  # 受付日は登録時に日本時間の今日を入れる。DB の CURRENT_DATE は RDS では UTC になるため使わない（データ設計書 5.4）
  before_validation :set_received_on, on: :create

  scope :in_display_order, -> { order(:display_order) }

  # 優先度 → 対応期限の近い順（未設定は後ろ）に並べる。どちらも同じものは今の順序を保つ（機能要件書 3.1）。
  # sort_by は安定ソートではないため、元の位置を最後の比較の材料に加える（API 設計書 14.）
  def self.sort_by_priority(inquiries)
    inquiries.each_with_index.sort_by do |inquiry, index|
      [
        PRIORITY_RANK.fetch(inquiry.priority),
        inquiry.due_on.nil? ? 1 : 0,
        inquiry.due_on || Date.new(0),
        index
      ]
    end.map(&:first)
  end

  # 並べた順に display_order を 0 から振り直して保存する（データ設計書 6.1）。
  # 位置やリストが変わったものだけを保存するので、updated_at も変わったものだけが更新される
  def self.renumber!(inquiries)
    inquiries.each_with_index do |inquiry, index|
      inquiry.display_order = index
      inquiry.save! if inquiry.changed?
    end
  end

  # ロックを待つ間に、問い合わせがほかのリストへ動かされていた
  class ListMoved < StandardError; end

  # 表示順を振り直すトランザクション（データ設計書 6.）。
  # 問い合わせが動かされていた、またはデッドロックで MySQL が取り消したときは、最初からやり直す。
  # やり直しに備えて、ブロックの中では lock_lists! で読み直してから値を書き込む
  def self.reorder_transaction(attempts: 5)
    attempts.times do |attempt|
      return transaction { yield }
    rescue ListMoved, ActiveRecord::Deadlocked
      raise if attempt == attempts - 1
    end
  end

  # 関係するリストの lists の行を行ロックし、この問い合わせを読み直す（データ設計書 6.2）。
  # 複数の行は 1 つの SQL でまとめてロックし、どの操作でもロックを取る順序を同じにする。
  # 読み直したら別のリストへ動かされていた場合、そのリストを後からロックすると順序が崩れるため、
  # ListMoved を投げてトランザクションごとやり直す（読み直した list_id で次はロックする）
  def lock_lists!(*other_list_ids)
    list_ids = [ list_id, *other_list_ids ].uniq
    List.where(id: list_ids).lock.load
    reload
    raise ListMoved unless list_ids.include?(list_id)
  end

  # 同じリストのほかの問い合わせ（表示順）
  def siblings
    Inquiry.where(list_id: list_id).where.not(id: id).in_display_order.to_a
  end

  private

  def set_received_on
    self.received_on ||= Time.zone.today
  end

  # date の列は、日付として読めない文字列を黙って nil にするため、受け取った値そのものを確かめる
  def due_on_must_be_date
    raw = due_on_before_type_cast
    return if raw.nil? || raw.is_a?(Date) || raw == ""

    valid = raw.is_a?(String) && raw.match?(/\A\d{4}-\d{2}-\d{2}\z/) && Date.valid_date?(*raw.split("-").map(&:to_i))
    errors.add(:due_on, :invalid_date) unless valid
  end
end
