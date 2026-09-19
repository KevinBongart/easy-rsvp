require 'rails_helper'
require Rails.root.join('db/migrate/20260919160000_add_persisted_invariant_checks')
require Rails.root.join('db/migrate/20260919160100_validate_persisted_invariant_checks')
require Rails.root.join('db/migrate/20260919160200_enforce_persisted_invariant_nullability')
require 'securerandom'

class PersistedInvariantsMigrationSpecRecord < ActiveRecord::Base
  self.abstract_class = true
end

RSpec.describe 'Persisted invariant migrations' do
  let(:connection) { PersistedInvariantsMigrationSpecRecord.connection }

  around do |example|
    schema = "persisted_invariants_migration_spec_#{SecureRandom.hex(6)}"
    PersistedInvariantsMigrationSpecRecord.establish_connection(
      ActiveRecord::Base.connection_db_config.configuration_hash
    )
    connection.create_schema(schema)
    connection.schema_search_path = schema
    create_tables

    example.run
  ensure
    if PersistedInvariantsMigrationSpecRecord.connected?
      connection.schema_search_path = 'public'
      connection.drop_schema(schema, if_exists: true, force: :cascade)
      PersistedInvariantsMigrationSpecRecord.connection_pool.disconnect!
    end
  end

  it 'protects new writes without scanning or rewriting invalid historical rows' do
    connection.execute("INSERT INTO events (published) VALUES (NULL)")
    connection.execute("INSERT INTO rsvps (event_id, name) VALUES (NULL, ' ')")

    migrate(AddPersistedInvariantChecks)

    expect(connection.select_value('SELECT count(*) FROM events')).to eq(1)
    expect(connection.select_value('SELECT count(*) FROM rsvps')).to eq(1)
    expect(constraint(:events, 'events_published_not_null').options[:validate]).to be(false)
    expect(constraint(:rsvps, 'rsvps_event_id_not_null').options[:validate]).to be(false)
    expect(constraint(:rsvps, 'rsvps_name_present').options[:validate]).to be(false)

    expect_check_violation { connection.execute("INSERT INTO events (published) VALUES (NULL)") }
    expect_check_violation { connection.execute("INSERT INTO rsvps (event_id, name) VALUES (NULL, 'Guest')") }
    expect_check_violation { connection.execute("INSERT INTO rsvps (event_id, name) VALUES (1, '   ')") }
  end

  it 'fails validation rather than coercing invalid historical data' do
    connection.execute("INSERT INTO events (published) VALUES (NULL)")
    connection.execute("INSERT INTO rsvps (event_id, name) VALUES (NULL, 'Guest')")
    migrate(AddPersistedInvariantChecks)

    validate_migration = migration(ValidatePersistedInvariantChecks)
    expect do
      connection.transaction(requires_new: true) do
        validate_migration.suppress_messages { validate_migration.up }
      end
    end
      .to raise_error(ActiveRecord::StatementInvalid) { |error| expect(error.cause).to be_a(PG::CheckViolation) }
  end

  it 'validates clean data before making columns non-null' do
    connection.execute("INSERT INTO events (published) VALUES (TRUE)")
    connection.execute("INSERT INTO rsvps (event_id, name) VALUES (1, 'Guest')")

    migrate(AddPersistedInvariantChecks)
    validate_migration = migration(ValidatePersistedInvariantChecks)
    validate_migration.suppress_messages { validate_migration.up }
    enforce_migration = migration(EnforcePersistedInvariantNullability)
    enforce_migration.suppress_messages { enforce_migration.up }

    expect(connection.columns(:events).find { |column| column.name == 'published' }.null).to be(false)
    expect(connection.columns(:rsvps).find { |column| column.name == 'event_id' }.null).to be(false)
    expect(connection.columns(:rsvps).find { |column| column.name == 'name' }.null).to be(false)
    expect(constraint(:rsvps, 'rsvps_name_present').options[:validate]).to be(true)
    expect(constraint(:rsvps, 'rsvps_event_id_not_null')).to be_nil
    expect(constraint(:events, 'events_published_not_null')).to be_nil
  end

  private

  def create_tables
    connection.create_table(:events) { |table| table.boolean :published }
    connection.create_table(:rsvps) do |table|
      table.bigint :event_id
      table.string :name
    end
  end

  def migration(migration_class)
    target_connection = connection
    migration_class.new.tap do |instance|
      instance.define_singleton_method(:connection) { target_connection }
    end
  end

  def migrate(migration_class)
    instance = migration(migration_class)
    instance.suppress_messages { instance.migrate(:up) }
  end

  def constraint(table, name)
    connection.check_constraints(table).find { |candidate| candidate.name == name }
  end

  def expect_check_violation(&block)
    expect do
      connection.transaction(requires_new: true, &block)
    end.to raise_error(ActiveRecord::StatementInvalid) { |error| expect(error.cause).to be_a(PG::CheckViolation) }
  end
end
