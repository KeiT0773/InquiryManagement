# CORS：開発時だけ、Next.js の開発サーバー（http://localhost:3000）からの呼び出しを許可する。
# 本番は CloudFront で画面と API が同じドメインのため、許可しない（API 設計書 2. 方針 10）。
if Rails.env.development?
  Rails.application.config.middleware.insert_before 0, Rack::Cors do
    allow do
      origins "http://localhost:3000"

      resource "/api/*",
        headers: :any,
        methods: %i[get post put patch delete options head]
    end
  end
end
