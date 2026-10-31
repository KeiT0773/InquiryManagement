-- ローカル開発用。MySQL のコンテナを初めて起動したときだけ実行される。
-- Rails の開発用ユーザーが、テスト用 DB（inquirymanagement_test）を作り直せるように権限を与える。
GRANT ALL PRIVILEGES ON `inquirymanagement\_%`.* TO 'inquirymanagement'@'%';
FLUSH PRIVILEGES;
