# すべての API の親。失敗したときは RFC 9457 の Problem Details の形式で返す（API 設計書 2.1）。
# コントローラーに届く前に起きる失敗（存在しない URL、UTF-8 でない body など）は
# lib/problem_details_exceptions_app.rb が同じ形式にする。
class ApplicationController < ActionController::API
  # rescue_from は後に書いたものが優先されるため、すべての例外を受ける StandardError を最初に書く
  rescue_from StandardError, with: :render_internal_error
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid
  rescue_from ActionDispatch::Http::Parameters::ParseError, with: :render_bad_request

  private

  # Problem Details の本文を組み立てて返す。errors は入力チェックのエラー（422）のときだけ付ける
  def render_problem(status, detail, errors: nil)
    code = Rack::Utils.status_code(status)
    body = {
      title: Rack::Utils::HTTP_STATUS_CODES[code],
      status: code,
      detail: detail,
      instance: request.path
    }
    body[:errors] = errors if errors
    render json: body, status: code, content_type: "application/problem+json"
  end

  # 入力チェックのエラー（422）。errors は { field:（要求 body の項目名）, message: } の配列。
  # detail は項目ごとのメッセージを「、」でつないだもので、画面はこれをそのまま表示する
  def render_unprocessable(errors, detail: errors.pluck(:message).join("、"))
    render_problem(:unprocessable_content, detail, errors: errors)
  end

  def render_record_invalid(error)
    errors = error.record.errors.map do |e|
      { field: api_field_name(e.attribute), message: e.full_message }
    end
    render_unprocessable(errors)
  end

  # モデルの項目名（customer_name）を要求 body の項目名（customerName）にする
  def api_field_name(attribute)
    attribute == :list ? "listId" : attribute.to_s.camelize(:lower)
  end

  def render_not_found(error)
    name = error.model&.safe_constantize&.model_name&.human || "データ"
    render_problem(:not_found, "#{name}が見つかりません: id=#{error.id}")
  end

  def render_bad_request(_error)
    render_problem(:bad_request, "要求の本文を JSON として読めません")
  end

  # DB に接続できないなど。原因はログにだけ書き、応答には出さない
  def render_internal_error(error)
    Rails.logger.error([ "#{error.class}: #{error.message}", *error.backtrace&.first(20) ].join("\n"))
    render_problem(:internal_server_error, "サーバーでエラーが発生しました")
  end
end
