class RemoveLegacyBodyFromEvents < ActiveRecord::Migration[8.1]
  def change
    remove_column :events, :body, :text
  end
end
