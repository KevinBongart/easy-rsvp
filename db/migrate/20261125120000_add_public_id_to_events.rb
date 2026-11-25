# Public event links used hashids of the sequential id, salted only with the
# table name, so anyone could compute every event's URL. Events get a random
# public id instead (96 bits, as 24 hex characters, which never contain the
# hyphen that starts the title slug). The database generates it: adding the
# column fills every existing row with its own value, and the release still
# running during the deploy keeps creating valid events.
#
# legacy_hashid_link marks the events whose hashid links were handed out, so
# those links keep working. The default covers existing rows and events the
# previous release creates during the deploy; Event sets false for new ones.
class AddPublicIdToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :public_id, :string, null: false, default: -> { "encode(gen_random_bytes(12), 'hex')" }
    add_index :events, :public_id, unique: true
    add_column :events, :legacy_hashid_link, :boolean, null: false, default: true
  end
end
