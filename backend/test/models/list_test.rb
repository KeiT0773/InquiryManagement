require "test_helper"

class ListTest < ActiveSupport::TestCase
  test "ボードの並び順で 3 件を取り出せる" do
    assert_equal %w[open working closed], List.ordered.pluck(:id)
  end

  test "問い合わせは表示順に並ぶ" do
    assert_equal [ inquiries(:login), inquiries(:invoice) ], lists(:open).inquiries.to_a
  end

  test "問い合わせが属しているリストは削除できない" do
    assert_raises(ActiveRecord::DeleteRestrictionError) { lists(:open).destroy }
  end

  test "DB の外部キーも、問い合わせが属しているリストの削除を拒否する" do
    assert_raises(ActiveRecord::InvalidForeignKey) { lists(:open).delete }
  end
end
