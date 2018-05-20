class CreateEvents < ActiveRecord::Migration[5.2]
  def change
    create_table :events do |t|
      t.string :title, null: false
      t.date :date, null: false
      t.text :body
      t.string :admin_token, null: false

      t.timestamps
    end
  end
end
