class AddShowRsvpNamesToEvents < ActiveRecord::Migration[6.1]
  def change
    add_column :events, :show_rsvp_names, :boolean, default: true, null: false
  end
end
