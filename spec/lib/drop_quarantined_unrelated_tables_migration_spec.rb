require 'rails_helper'
require Rails.root.join('db/migrate/20260915103000_quarantine_unrelated_tables')
require Rails.root.join('db/migrate/20260919170000_drop_quarantined_unrelated_tables')
require 'securerandom'

class DropQuarantinedTablesMigrationSpecRecord < ActiveRecord::Base
  self.abstract_class = true
end

RSpec.describe DropQuarantinedUnrelatedTables do
  let(:connection) { DropQuarantinedTablesMigrationSpecRecord.connection }
  let(:migration) do
    target_connection = connection
    described_class.new.tap do |instance|
      instance.define_singleton_method(:connection) { target_connection }
    end
  end

  around do |example|
    schema = "drop_quarantined_tables_migration_spec_#{SecureRandom.hex(6)}"
    DropQuarantinedTablesMigrationSpecRecord.establish_connection(
      ActiveRecord::Base.connection_db_config.configuration_hash
    )
    connection.create_schema(schema)
    connection.schema_search_path = schema

    example.run
  ensure
    if DropQuarantinedTablesMigrationSpecRecord.connected?
      connection.schema_search_path = 'public'
      connection.drop_schema(schema, if_exists: true, force: :cascade)
      DropQuarantinedTablesMigrationSpecRecord.connection_pool.disconnect!
    end
  end

  it 'covers every table created by the quarantine migration' do
    expected_tables = QuarantineUnrelatedTables::TABLES.map do |table|
      "#{QuarantineUnrelatedTables::PREFIX}#{table}"
    end

    expect(described_class::TABLES).to eq(expected_tables)
  end

  it 'is a no-op on a fresh database without quarantined tables' do
    connection.create_table(:events)

    expect { migration.suppress_messages { migration.up } }.not_to raise_error
    expect(connection.table_exists?(:events)).to be(true)
  end

  it 'drops every quarantined table together with internal relationships' do
    described_class::TABLES.each { |table| connection.create_table(table) }
    connection.add_column :quarantined_20260915_card_games, :game_id, :bigint
    connection.add_foreign_key :quarantined_20260915_card_games, :quarantined_20260915_games,
      column: :game_id
    connection.execute('INSERT INTO quarantined_20260915_games DEFAULT VALUES')
    connection.execute('INSERT INTO quarantined_20260915_card_games (game_id) VALUES (1)')
    connection.create_table(:events)

    migration.suppress_messages { migration.up }

    expect(described_class::TABLES).to all(satisfy { |table| !connection.table_exists?(table) })
    expect(connection.table_exists?(:events)).to be(true)
  end

  it 'refuses to cascade through an unexpected external foreign key' do
    connection.create_table(:quarantined_20260915_games)
    connection.create_table(:unexpected_records) { |table| table.bigint :game_id }
    connection.add_foreign_key :unexpected_records, :quarantined_20260915_games, column: :game_id

    expect do
      connection.transaction(requires_new: true) { migration.suppress_messages { migration.up } }
    end
      .to raise_error(ActiveRecord::StatementInvalid) do |error|
        expect(error.cause).to be_a(PG::DependentObjectsStillExist)
      end
    expect(connection.table_exists?(:quarantined_20260915_games)).to be(true)
    expect(connection.table_exists?(:unexpected_records)).to be(true)
  end

  it 'is irreversible' do
    expect { migration.down }.to raise_error(
      ActiveRecord::IrreversibleMigration,
      /cannot be restored/
    )
  end
end
