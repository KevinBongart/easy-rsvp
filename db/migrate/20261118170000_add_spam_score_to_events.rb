# Jev's "is this advertising?" score (0 to 1) from the background spam review,
# kept so the dashboard can show why an event was flagged.
class AddSpamScoreToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :spam_score, :float
  end
end
