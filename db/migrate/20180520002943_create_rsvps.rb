class CreateRsvps < ActiveRecord::Migration[5.2]
  def change
    create_table :rsvps do |t|
      t.references :event, foreign_key: true
      t.string :name
      t.string :response

      t.timestamps
    end
  end
end
