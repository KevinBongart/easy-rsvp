class CreateEvents < ActiveRecord::Migration[5.2]
  def change
    create_table :events do |t|
      t.string :title, null: false
      t.string :date
      t.text :body
      t.string :admin_token, null: false

      t.timestamps
    end
  end
end
