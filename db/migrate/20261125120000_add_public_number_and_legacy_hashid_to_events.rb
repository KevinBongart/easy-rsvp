# Public event links used hashids of the sequential id, salted only with the
# table name, so anyone could compute every event's URL. Links now encode a
# random public_number instead (see Event::LINK_IDS).
#
# The database generates public_number (48 random bits): adding the column
# fills every existing row with its own value, and the release still running
# during the deploy keeps creating valid events. If two rows ever drew the
# same number (about 1 in 2 million for today's 18,000 events), the unique
# index fails, this migration rolls back, and deploying again redraws them.
#
# legacy_hashid keeps the hashid links already handed out working. Every
# existing event gets its hashid stored here, computed exactly as hashid-rails
# does for Event, so lookups need no hashid decoding. The column default ""
# marks events the previous release creates after this migration and before
# it stops serving: their creators received hashid links too, and
# Event.find_by_link_id! stores the hashid the first time one is followed.
# Event writes nil for the events it creates, which have no legacy link.
class AddPublicNumberAndLegacyHashidToEvents < ActiveRecord::Migration[8.1]
  # hashid-rails' settings for Event: the table name as salt, at least 6
  # characters, the default alphabet, and each id signed with 42.
  LEGACY_HASHIDS = Hashids.new("events", 6)
  LEGACY_HASHID_SIGNATURE = 42
  BATCH_SIZE = 1_000

  def up
    add_column :events, :public_number, :bigint, null: false,
      default: -> { "('x' || encode(gen_random_bytes(6), 'hex'))::bit(48)::bigint" }
    add_index :events, :public_number, unique: true

    add_column :events, :legacy_hashid, :string, default: ""
    # The migration's transaction holds the lock add_column took, so no event
    # can be created between the backfill and the commit.
    select_values("SELECT id FROM events ORDER BY id").each_slice(BATCH_SIZE) do |ids|
      rows = ids.map { |id| "(#{Integer(id)}, #{quote(LEGACY_HASHIDS.encode(LEGACY_HASHID_SIGNATURE, id))})" }
      execute <<~SQL.squish
        UPDATE events SET legacy_hashid = backfill.hashid
        FROM (VALUES #{rows.join(", ")}) AS backfill (id, hashid)
        WHERE events.id = backfill.id
      SQL
    end
    add_index :events, :legacy_hashid, unique: true, where: "legacy_hashid <> ''"
  end

  def down
    remove_column :events, :legacy_hashid
    remove_column :events, :public_number
  end
end
