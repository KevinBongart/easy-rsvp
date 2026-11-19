# The admin dashboard filters events by creation time (the daily chart and the
# current-month statistics); without an index every load scans the whole table.
class AddCreatedAtIndexToEvents < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :events, :created_at, algorithm: :concurrently
  end
end
