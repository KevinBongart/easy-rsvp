# Remembers that an event was once confidently flagged as spam, so an edit
# that drops it below the bar does not reveal the verdict to its organizer.
class AddSpamVerdictHiddenToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :spam_verdict_hidden, :boolean, default: false, null: false
  end
end
