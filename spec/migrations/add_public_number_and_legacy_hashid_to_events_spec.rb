require 'rails_helper'
require Rails.root.join('db/migrate/20261125120000_add_public_number_and_legacy_hashid_to_events')

RSpec.describe AddPublicNumberAndLegacyHashidToEvents do
  let(:connection) { ActiveRecord::Base.connection }

  # Runs on the schema before this migration, in the example's transaction.
  before do
    stub_const("#{described_class}::BATCH_SIZE", 2)
    migrate(:down)
  end

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  def insert_event(title)
    connection.select_value(<<~SQL.squish)
      INSERT INTO events (title, date, admin_token, created_at, updated_at)
      VALUES (#{connection.quote(title)}, CURRENT_DATE, gen_random_uuid(), now(), now())
      RETURNING id
    SQL
  end

  def event_rows
    connection.select_rows('SELECT id, public_number, legacy_hashid FROM events ORDER BY id')
  end

  it "stores each existing event's hashid, in batches, and gives each a random public number" do
    ids = Array.new(5) { |index| insert_event("Party #{index}") }

    migrate(:up)

    expect(event_rows.map(&:first)).to eq(ids)
    expect(event_rows.map(&:last)).to eq(ids.map { |id| Event.encode_id(id) })
    public_numbers = event_rows.map(&:second)
    expect(public_numbers).to all(be_between(0, 2**48 - 1))
    expect(public_numbers.uniq.size).to eq(ids.size)
  end

  it 'marks events the previous release creates afterwards as pending, and lets several exist' do
    migrate(:up)
    2.times { |index| insert_event("Mid-deploy #{index}") }

    expect(event_rows.map(&:last)).to all(eq(Event::PENDING_LEGACY_HASHID))
    expect(event_rows.map(&:second).uniq.size).to eq(2)
  end

  it 'keeps stored hashids unique' do
    insert_event('Party')
    migrate(:up)
    hashid = event_rows.sole.last
    insert_event('Copy')

    expect {
      connection.execute("UPDATE events SET legacy_hashid = #{connection.quote(hashid)} WHERE legacy_hashid = ''")
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'rolls back to the previous columns' do
    insert_event('Party')
    migrate(:up)
    migrate(:down)

    expect(connection.column_exists?(:events, :public_number)).to be(false)
    expect(connection.column_exists?(:events, :legacy_hashid)).to be(false)
    expect(connection.select_value('SELECT count(*) FROM events')).to eq(1)
  end
end
