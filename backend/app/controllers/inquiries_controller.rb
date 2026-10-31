# 問い合わせの API（API 設計書 6.〜12.）。
# 表示順を振り直す操作は、1 つのトランザクションの中で対象のリストの行をロックしてから行う（データ設計書 6.）
class InquiriesController < ApplicationController
  # 要求 body の項目名（camelCase）とモデルの項目名（snake_case）の対応（API 設計書 2. 方針 3）
  FIELDS = {
    "title" => :title,
    "customerName" => :customer_name,
    "contact" => :contact,
    "category" => :category,
    "content" => :content,
    "memo" => :memo,
    "assignee" => :assignee,
    "dueOn" => :due_on,
    "priority" => :priority
  }.freeze
  # 登録で受け取る項目。ほかの項目は送られても無視する（API 設計書 8.）
  CREATE_FIELDS = %w[title customerName content category priority].freeze

  # GET /api/inquiries（6.）。リストの並び順 → リスト内の表示順で返す
  def index
    inquiries = Inquiry.joins(:list).order(List.arel_table[:display_order], :display_order)
    inquiries = inquiries.where(list_id: params[:listId]) if params[:listId].is_a?(String)
    render json: inquiries.map { |inquiry| serialize(inquiry) }
  end

  # GET /api/inquiries/{id}（7.）
  def show
    render json: serialize(find_inquiry)
  end

  # POST /api/inquiries（8.）。「未対応」の末尾に入れてから優先度順に並べ直す
  def create
    attributes = inquiry_attributes(CREATE_FIELDS)
    attributes[:category] ||= "question"
    attributes[:priority] ||= "medium"

    inquiry = Inquiry.reorder_transaction do
      List.lock.find(List::REGISTER_LIST_ID)
      siblings = Inquiry.where(list_id: List::REGISTER_LIST_ID).in_display_order.to_a
      created = Inquiry.create!(attributes.merge(list_id: List::REGISTER_LIST_ID, display_order: siblings.size))
      Inquiry.renumber!(Inquiry.sort_by_priority(siblings + [ created ]))
      created
    end
    render json: serialize(inquiry), status: :created, location: "/api/inquiries/#{inquiry.id}"
  end

  # PATCH /api/inquiries/{id}（9.）。送られた項目だけを変える。優先度が変わったときだけリスト内を並べ直す
  def update
    inquiry = find_inquiry
    attributes = inquiry_attributes(FIELDS.keys)
    return render_unprocessable([], detail: "変更する項目を指定してください") if attributes.empty?

    Inquiry.reorder_transaction do
      inquiry.lock_lists! if attributes.key?(:priority)
      inquiry.assign_attributes(attributes)
      inquiry.validate!
      if inquiry.priority_changed?
        # 末尾に移してから並べ直し、変更後の優先度のまとまりの末尾に入れる（FR-08）
        Inquiry.renumber!(Inquiry.sort_by_priority(inquiry.siblings + [ inquiry ]))
      else
        inquiry.save!
      end
    end
    render json: serialize(inquiry)
  end

  # PUT /api/inquiries/{id}/position（10.）。指定した位置にそのまま置き、優先度順には並べ直さない
  def position
    inquiry = find_inquiry
    body = request.request_parameters
    list_id = body["listId"]
    display_order = body["displayOrder"]

    errors = []
    unless list_id.is_a?(String) && list_id.present?
      errors << { field: "listId", message: "移動先のリストを指定してください" }
    end
    unless display_order.nil? || (display_order.is_a?(Integer) && display_order >= 0)
      errors << { field: "displayOrder", message: "表示順は0以上の整数で指定してください" }
    end
    return render_unprocessable(errors) if errors.any?

    destination_list = List.find_by(id: list_id)
    unless destination_list
      return render_unprocessable([ { field: "listId", message: "リストが見つかりません: listId=#{list_id}" } ])
    end

    Inquiry.reorder_transaction do
      # 照合順序が大文字小文字を区別しないため、保存には DB にある id（open など）を使う
      inquiry.lock_lists!(destination_list.id)
      same_list = inquiry.list_id == destination_list.id
      source = inquiry.siblings
      destination = same_list ? source : Inquiry.where(list_id: destination_list.id).in_display_order.to_a
      # 位置は「自分を除いた並び」の何番目か。件数以上または指定なしなら末尾（API 設計書 10.）
      destination.insert([ display_order || destination.size, destination.size ].min, inquiry)
      inquiry.list_id = destination_list.id
      Inquiry.renumber!(source) unless same_list
      Inquiry.renumber!(destination)
    end
    render json: serialize(inquiry)
  end

  # POST /api/inquiries/sort（11.）。3 つのリストをそれぞれ優先度順に並べ直す
  def sort
    Inquiry.reorder_transaction do
      List.ordered.lock.to_a.each do |list|
        Inquiry.renumber!(Inquiry.sort_by_priority(Inquiry.where(list_id: list.id).in_display_order.to_a))
      end
    end
    head :no_content
  end

  # DELETE /api/inquiries/{id}（12.）。削除したあと、残りの表示順を詰める
  def destroy
    inquiry = find_inquiry
    Inquiry.reorder_transaction do
      inquiry.lock_lists!
      inquiry.destroy!
      Inquiry.renumber!(inquiry.siblings)
    end
    head :no_content
  end

  private

  # id が数値でないときも、該当する問い合わせが無いものとして 404 にする（API 設計書 2.2）。
  # find は "1abc" を 1 と読むため、数字だけかを先に確かめる
  def find_inquiry
    id = params[:id]
    raise ActiveRecord::RecordNotFound.new(nil, "Inquiry", "id", id) unless id.match?(/\A\d+\z/)

    Inquiry.find(id)
  end

  # 要求 body から、fields のうち送られた項目だけを取り出す。
  # 「送らない」（変えない）と「null を送る」（値を消す）を区別するため、キーの有無で判定する（API 設計書 9.）
  def inquiry_attributes(fields)
    body = request.request_parameters
    attributes = fields.select { |field| body.key?(field) }.to_h { |field| [ FIELDS.fetch(field), body[field] ] }

    nested = attributes.select { |_, value| value.is_a?(Hash) || value.is_a?(Array) }.keys
    if nested.any?
      record = Inquiry.new
      nested.each { |attribute| record.errors.add(attribute, :invalid) }
      raise ActiveRecord::RecordInvalid, record
    end
    attributes
  end

  # 4.2 の形式。値が無い項目も null で含める
  def serialize(inquiry)
    {
      id: inquiry.id,
      title: inquiry.title,
      customerName: inquiry.customer_name,
      contact: inquiry.contact,
      category: inquiry.category,
      content: inquiry.content,
      memo: inquiry.memo,
      assignee: inquiry.assignee,
      receivedOn: inquiry.received_on.iso8601,
      dueOn: inquiry.due_on&.iso8601,
      priority: inquiry.priority,
      listId: inquiry.list_id,
      displayOrder: inquiry.display_order,
      createdAt: inquiry.created_at.utc.iso8601(3),
      updatedAt: inquiry.updated_at.utc.iso8601(3)
    }
  end
end
