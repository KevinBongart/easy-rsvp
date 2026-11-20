# Links each creation counter to the event it created, and records when that
# event became spam, so the client can be refused for a while. The link lives
# only here and disappears with the counter; deleting an event keeps its
# counter, unlinked, and keeps its spam_at.
class AddEventToRecentEventCreations < ActiveRecord::Migration[8.1]
  def change
    add_reference :recent_event_creations, :event, null: true, index: true,
      foreign_key: { on_delete: :nullify }
    add_column :recent_event_creations, :spam_at, :datetime
  end
end
