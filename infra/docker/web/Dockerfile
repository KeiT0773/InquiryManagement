# web イメージ：nginx + 画面の静的ファイル（インフラ設計書 7.3）。本番でだけ使う。
# 画面のファイルは別の場所（frontend/out）にあるため、名前付きのビルドコンテキスト（site）で渡す。
#   cd frontend && npm run build
#   docker build --build-context site=frontend/out -t <ECR>/inquirymanagement-web:<タグ> infra/docker/web
# infra/scripts/deploy-frontend.sh・startup.sh がこの手順を行う。
FROM nginx:1.28-alpine

# nginx の公式イメージは、起動時に /etc/nginx/templates/*.template の環境変数（${ORIGIN_VERIFY}）を
# 値に置き換えて /etc/nginx/conf.d/ に書き出す。定義されていない変数（nginx の $uri など）はそのまま残る
COPY default.conf.template /etc/nginx/templates/default.conf.template

COPY --from=site . /usr/share/nginx/html
