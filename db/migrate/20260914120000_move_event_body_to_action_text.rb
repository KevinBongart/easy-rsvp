class MoveEventBodyToActionText < ActiveRecord::Migration[8.1]
  def up
    create_table :action_text_rich_texts do |t|
      t.string :name, null: false
      t.text :body
      t.references :record, null: false, polymorphic: true, index: false
      t.timestamps

      t.index [ :record_type, :record_id, :name ],
        name: "index_action_text_rich_texts_uniqueness",
        unique: true
    end

    execute <<~SQL.squish
      INSERT INTO action_text_rich_texts
        (name, body, record_type, record_id, created_at, updated_at)
      SELECT
        'body', body, 'Event', id, created_at, updated_at
      FROM events
      WHERE body IS NOT NULL AND body <> ''
    SQL

    remove_column :events, :body, :text
  end

  def down
    add_column :events, :body, :text

    execute <<~SQL.squish
      UPDATE events
      SET body = action_text_rich_texts.body
      FROM action_text_rich_texts
      WHERE action_text_rich_texts.record_type = 'Event'
        AND action_text_rich_texts.record_id = events.id
        AND action_text_rich_texts.name = 'body'
    SQL

    drop_table :action_text_rich_texts
  end
end
