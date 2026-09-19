class EnforcePersistedInvariantNullability < ActiveRecord::Migration[8.1]
  def up
    change_column_null :rsvps, :event_id, false
    change_column_null :rsvps, :name, false
    change_column_null :events, :published, false

    remove_check_constraint :rsvps, name: "rsvps_event_id_not_null"
    remove_check_constraint :events, name: "events_published_not_null"
  end

  def down
    change_column_null :rsvps, :event_id, true
    change_column_null :rsvps, :name, true
    change_column_null :events, :published, true

    add_check_constraint :rsvps, "event_id IS NOT NULL",
      name: "rsvps_event_id_not_null"
    add_check_constraint :events, "published IS NOT NULL",
      name: "events_published_not_null"
  end
end
