class RemoveLegacyBodyFromEvents < ActiveRecord::Migration[8.1]
  def up
    create_table :legacy_event_body_conflicts do |t|
      t.references :event,
        null: false,
        index: { unique: true },
        foreign_key: { on_delete: :cascade }
      t.text :body, null: false
      t.datetime :event_updated_at, null: false
      t.datetime :action_text_updated_at, null: false
      t.datetime :created_at, null: false
    end

    # The previous web process can still write events.body while a new release
    # migrates. Hold both tables for the short reconciliation so no cutover write
    # can land between the copy and the column removal.
    execute "LOCK TABLE events, action_text_rich_texts IN ACCESS EXCLUSIVE MODE"

    execute <<~SQL.squish
      INSERT INTO action_text_rich_texts
        (name, body, record_type, record_id, created_at, updated_at)
      SELECT
        'body', events.body, 'Event', events.id,
        events.created_at, events.updated_at
      FROM events
      LEFT JOIN action_text_rich_texts
        ON action_text_rich_texts.record_type = 'Event'
        AND action_text_rich_texts.record_id = events.id
        AND action_text_rich_texts.name = 'body'
      WHERE action_text_rich_texts.id IS NULL
        AND events.body IS NOT NULL
        AND events.body <> ''
      ON CONFLICT (record_type, record_id, name) DO NOTHING
    SQL

    # Action Text is authoritative after cutover. Preserve any different legacy
    # value for explicit inspection instead of guessing which version is newer.
    execute <<~SQL.squish
      INSERT INTO legacy_event_body_conflicts
        (event_id, body, event_updated_at, action_text_updated_at, created_at)
      SELECT
        events.id, events.body, events.updated_at,
        action_text_rich_texts.updated_at, CURRENT_TIMESTAMP
      FROM events
      INNER JOIN action_text_rich_texts
        ON action_text_rich_texts.record_type = 'Event'
        AND action_text_rich_texts.record_id = events.id
        AND action_text_rich_texts.name = 'body'
      WHERE events.body IS NOT NULL
        AND events.body <> ''
        AND action_text_rich_texts.body IS DISTINCT FROM events.body
      ON CONFLICT (event_id) DO NOTHING
    SQL

    conflict_count = select_value("SELECT count(*) FROM legacy_event_body_conflicts")
    say "Preserved #{conflict_count} divergent legacy event descriptions"

    remove_column :events, :body, :text
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Action Text and legacy event descriptions cannot be merged losslessly"
  end
end
