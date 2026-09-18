require 'rails_helper'
require Rails.root.join('db/migrate/20260918153000_remove_legacy_body_from_events')
require 'securerandom'

class RemoveLegacyBodyMigrationSpecRecord < ActiveRecord::Base
  self.abstract_class = true
end

RSpec.describe RemoveLegacyBodyFromEvents do
  let(:connection) { RemoveLegacyBodyMigrationSpecRecord.connection }
  let(:migration) do
    described_class.new.tap do |instance|
      instance.instance_variable_set(:@connection, connection)
    end
  end
  let(:old_time) { Time.utc(2026, 9, 1, 12) }
  let(:new_time) { Time.utc(2026, 9, 16, 12) }

  around do |example|
    schema = "remove_legacy_body_migration_spec_#{SecureRandom.hex(6)}"
    RemoveLegacyBodyMigrationSpecRecord.establish_connection(
      ActiveRecord::Base.connection_db_config.configuration_hash
    )
    connection.create_schema(schema)
    connection.schema_search_path = schema
    create_source_tables

    example.run
  ensure
    if RemoveLegacyBodyMigrationSpecRecord.connected?
      connection.schema_search_path = 'public'
      connection.drop_schema(schema, if_exists: true, force: :cascade)
      RemoveLegacyBodyMigrationSpecRecord.connection_pool.disconnect!
    end
  end

  it 'backfills missing text and preserves divergent legacy values before dropping the column' do
    missing_id = insert_event('<p>Missing <img src="legacy.png"></p>')
    equal_id = insert_event('<p>Equal</p>')
    divergent_id = insert_event('<p>Legacy version</p>', updated_at: new_time)
    cleared_id = insert_event('<p>Legacy before clear</p>', updated_at: new_time)
    blank_id = insert_event('')
    null_id = insert_event(nil)

    insert_rich_text(equal_id, '<p>Equal</p>')
    insert_rich_text(divergent_id, '<p>Action Text version</p>', updated_at: new_time)
    insert_rich_text(cleared_id, '', updated_at: new_time)
    insert_rich_text(equal_id, '<p>Unrelated</p>', name: 'summary')
    insert_rich_text(equal_id, '<p>Another record</p>', record_type: 'Other')

    migration.suppress_messages { migration.up }

    expect(connection.column_exists?(:events, :body)).to be(false)
    expect(rich_text_body(missing_id)).to eq('<p>Missing <img src="legacy.png"></p>')
    expect(rich_text_body(equal_id)).to eq('<p>Equal</p>')
    expect(rich_text_body(divergent_id)).to eq('<p>Action Text version</p>')
    expect(rich_text_body(cleared_id)).to eq('')
    expect(rich_text_body(blank_id)).to be_nil
    expect(rich_text_body(null_id)).to be_nil

    conflicts = connection.select_rows(<<~SQL.squish).to_h
      SELECT event_id::text, body
      FROM legacy_event_body_conflicts
      ORDER BY event_id
    SQL
    expect(conflicts).to eq(
      divergent_id.to_s => '<p>Legacy version</p>',
      cleared_id.to_s => '<p>Legacy before clear</p>'
    )
    expect(connection.select_values(<<~SQL.squish)).to contain_exactly('<p>Unrelated</p>', '<p>Another record</p>')
      SELECT body
      FROM action_text_rich_texts
      WHERE name = 'summary' OR record_type = 'Other'
    SQL

    connection.execute("DELETE FROM events WHERE id = #{connection.quote(divergent_id)}")
    expect(connection.select_value(<<~SQL.squish).to_i).to eq(0)
      SELECT count(*)
      FROM legacy_event_body_conflicts
      WHERE event_id = #{connection.quote(divergent_id)}
    SQL
  end

  it 'does not claim that conflicting descriptions can be rolled back losslessly' do
    expect { migration.down }
      .to raise_error(ActiveRecord::IrreversibleMigration, /cannot be merged losslessly/)
  end

  private

  def create_source_tables
    connection.create_table(:events) do |t|
      t.text :body
      t.timestamps null: false
    end
    connection.create_table(:action_text_rich_texts) do |t|
      t.string :name, null: false
      t.text :body
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.timestamps null: false
      t.index %i[record_type record_id name], unique: true,
        name: 'index_action_text_rich_texts_uniqueness'
    end
  end

  def insert_event(body, updated_at: old_time)
    connection.select_value(<<~SQL.squish).to_i
      INSERT INTO events (body, created_at, updated_at)
      VALUES (#{connection.quote(body)}, #{connection.quote(old_time)}, #{connection.quote(updated_at)})
      RETURNING id
    SQL
  end

  def insert_rich_text(record_id, body, name: 'body', record_type: 'Event', updated_at: old_time)
    connection.execute(<<~SQL.squish)
      INSERT INTO action_text_rich_texts
        (name, body, record_type, record_id, created_at, updated_at)
      VALUES (
        #{connection.quote(name)}, #{connection.quote(body)},
        #{connection.quote(record_type)}, #{connection.quote(record_id)},
        #{connection.quote(old_time)}, #{connection.quote(updated_at)}
      )
    SQL
  end

  def rich_text_body(record_id)
    connection.select_value(<<~SQL.squish)
      SELECT body
      FROM action_text_rich_texts
      WHERE record_type = 'Event'
        AND record_id = #{connection.quote(record_id)}
        AND name = 'body'
    SQL
  end
end
