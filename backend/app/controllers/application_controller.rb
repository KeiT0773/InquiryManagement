# すべての API の親。失敗したときは RFC 9457 の Problem Details の形式で返す（API 設計書 2.1）。
class ApplicationController < ActionController::API
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
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

  def render_not_found(error)
    name = error.model&.safe_constantize&.model_name&.human || "データ"
    render_problem(:not_found, "#{name}が見つかりません: id=#{error.id}")
  end

  def render_bad_request(_error)
    render_problem(:bad_request, "要求の本文を JSON として読めません")
  end
end
