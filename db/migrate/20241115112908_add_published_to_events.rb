class AddPublishedToEvents < ActiveRecord::Migration[7.2]
  def change
    add_column :events, :published, :boolean, default: true
  end
end
