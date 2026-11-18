# Short-lived per-client counters for event creation. Rows hold only a keyed
# one-way digest of the client address, are never linked to an event, and are
# deleted once they fall outside the rate-limit window.
class CreateRecentEventCreations < ActiveRecord::Migration[8.1]
  def change
    create_table :recent_event_creations do |t|
      t.string :client_digest, null: false
      t.datetime :created_at, null: false
    end

    add_index :recent_event_creations, [ :client_digest, :created_at ]
    add_index :recent_event_creations, :created_at
  end
end
