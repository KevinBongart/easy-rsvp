require 'rails_helper'
require Rails.root.join('db/migrate/20260915103000_quarantine_unrelated_tables')
require 'securerandom'

class QuarantineTablesMigrationSpecRecord < ActiveRecord::Base
  self.abstract_class = true
end

RSpec.describe QuarantineUnrelatedTables do
  let(:connection) { QuarantineTablesMigrationSpecRecord.connection }
  let(:migration) do
    described_class.new.tap do |instance|
      instance.instance_variable_set(:@connection, connection)
    end
  end

  around do |example|
    schema = "quarantine_tables_migration_spec_#{SecureRandom.hex(6)}"
    QuarantineTablesMigrationSpecRecord.establish_connection(
      ActiveRecord::Base.connection_db_config.configuration_hash
    )
    connection.create_schema(schema)
    connection.schema_search_path = schema

    example.run
  ensure
    if QuarantineTablesMigrationSpecRecord.connected?
      connection.schema_search_path = 'public'
      connection.drop_schema(schema, if_exists: true, force: :cascade)
      QuarantineTablesMigrationSpecRecord.connection_pool.disconnect!
    end
  end

  it 'quarantines the unrelated tables without losing data or relationships and restores them' do
    described_class::TABLES.each do |table|
      connection.create_table(table) do |t|
        t.bigint :game_id if table == 'card_games'
        if table == 'action_text_rich_texts'
          t.string :record_type, null: false
          t.string :record_id, null: false
          t.string :name, null: false
        end
      end
    end
    connection.add_index(
      :action_text_rich_texts,
      %i[record_type record_id name],
      unique: true,
      name: 'index_action_text_rich_texts_uniqueness'
    )
    connection.add_foreign_key :card_games, :games
    connection.execute("INSERT INTO games DEFAULT VALUES")
    connection.execute("INSERT INTO card_games (game_id) VALUES (1)")
    connection.execute(<<~SQL)
      INSERT INTO action_text_rich_texts (record_type, record_id, name)
      VALUES ('Entry', '1', 'description')
    SQL

    migration.suppress_messages { migration.up }

    expect(described_class::TABLES).to all(satisfy do |table|
      !connection.table_exists?(table) && connection.table_exists?("#{described_class::PREFIX}#{table}")
    end)
    expect(connection.select_value('SELECT count(*) FROM quarantined_20260915_card_games')).to eq(1)
    expect(connection.select_value('SELECT count(*) FROM quarantined_20260915_action_text_rich_texts')).to eq(1)
    expect(connection.foreign_keys(:quarantined_20260915_card_games).sole.to_table)
      .to eq('quarantined_20260915_games')
    expect(connection.index_name_exists?(
      :quarantined_20260915_action_text_rich_texts,
      'index_quarantined_20260915_action_text_rich_texts_uniqueness'
    )).to be(true)
    expect(connection.select_value(<<~SQL)).to end_with('.quarantined_20260915_action_text_rich_texts_id_seq')
      SELECT pg_get_serial_sequence('quarantined_20260915_action_text_rich_texts', 'id')
    SQL

    migration.suppress_messages { migration.down }

    expect(described_class::TABLES).to all(satisfy do |table|
      connection.table_exists?(table) && !connection.table_exists?("#{described_class::PREFIX}#{table}")
    end)
    expect(connection.select_value('SELECT count(*) FROM card_games')).to eq(1)
    expect(connection.foreign_keys(:card_games).sole.to_table).to eq('games')
    expect(connection.index_name_exists?(
      :action_text_rich_texts,
      'index_action_text_rich_texts_uniqueness'
    )).to be(true)
  end

  it 'does nothing when a clean Easy RSVP database has none of the unrelated tables' do
    connection.create_table(:events)

    expect { migration.suppress_messages { migration.up } }.not_to raise_error
    expect(connection.table_exists?(:events)).to be(true)
    expect(connection.tables.grep(/^quarantined_20260915_/)).to be_empty
  end
end
