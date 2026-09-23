class AddScheduleToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :starts_at, :datetime
    add_column :events, :ends_at, :datetime
    add_column :events, :time_zone, :string

    add_check_constraint :events,
      <<~SQL.squish,
        (starts_at IS NULL AND ends_at IS NULL AND time_zone IS NULL)
        OR
        (starts_at IS NOT NULL AND ends_at IS NOT NULL AND time_zone IS NOT NULL AND BTRIM(time_zone) <> '')
      SQL
      name: "events_schedule_complete"
    add_check_constraint :events,
      "ends_at IS NULL OR starts_at IS NULL OR ends_at > starts_at",
      name: "events_schedule_ordered"
    add_check_constraint :events,
      <<~SQL.squish,
        starts_at IS NULL
        OR
        (
          (starts_at AT TIME ZONE 'UTC' AT TIME ZONE time_zone)::date = date
          AND
          (ends_at AT TIME ZONE 'UTC' AT TIME ZONE time_zone)::date = date
        )
      SQL
      name: "events_schedule_matches_date"
  end
end
