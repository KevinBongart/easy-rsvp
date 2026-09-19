class ValidatePersistedInvariantChecks < ActiveRecord::Migration[8.1]
  def up
    validate_check_constraint :rsvps, name: "rsvps_event_id_not_null"
    validate_check_constraint :rsvps, name: "rsvps_name_present"
    validate_check_constraint :events, name: "events_published_not_null"
  end

  def down
    remove_check_constraint :rsvps, name: "rsvps_event_id_not_null"
    remove_check_constraint :rsvps, name: "rsvps_name_present"
    remove_check_constraint :events, name: "events_published_not_null"

    add_check_constraint :rsvps, "event_id IS NOT NULL",
      name: "rsvps_event_id_not_null", validate: false
    add_check_constraint :rsvps, "name IS NOT NULL AND btrim(name) <> ''",
      name: "rsvps_name_present", validate: false
    add_check_constraint :events, "published IS NOT NULL",
      name: "events_published_not_null", validate: false
  end
end
