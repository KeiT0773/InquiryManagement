# コントローラーの外で起きた失敗の応答を、Problem Details の形式（API 設計書 2.1）で返す。
# config.exceptions_app に設定する。存在しない URL（404）や、body が UTF-8 として読めない（400）など、
# ApplicationController の rescue_from より手前で起きたものがここに来る。
# 開発環境では Rails の詳しいエラー画面が先に出るため、ここは本番とテストで使われる。
#
# コントローラーを通すと、ログを書くときに同じ body を読み直して再び失敗するため、Rack のアプリとして書く
class ProblemDetailsExceptionsApp
  DETAILS = {
    400 => "要求を読めません",
    404 => "指定された URL はありません"
  }.freeze

  def self.call(env)
    request = ActionDispatch::Request.new(env)
    # Rails は "/404" のように、ステータスコードをパスにして呼ぶ
    status = request.path_info.delete_prefix("/").to_i
    status = 500 unless Rack::Utils::HTTP_STATUS_CODES.key?(status) && status >= 400

    body = {
      title: Rack::Utils::HTTP_STATUS_CODES[status],
      status: status,
      detail: DETAILS.fetch(status, "サーバーでエラーが発生しました"),
      instance: request.original_fullpath.split("?").first
    }
    [ status, { "content-type" => "application/problem+json" }, [ body.to_json ] ]
  end
end
