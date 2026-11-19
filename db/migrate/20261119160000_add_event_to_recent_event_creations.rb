# Links each creation counter to the event it created, so a client whose
# recent event is currently spam can be refused. The link lives only here and
# disappears with the counter; deleting an event keeps its counter, unlinked.
class AddEventToRecentEventCreations < ActiveRecord::Migration[8.1]
  def change
    add_reference :recent_event_creations, :event, null: true, index: true,
      foreign_key: { on_delete: :nullify }
  end
end
