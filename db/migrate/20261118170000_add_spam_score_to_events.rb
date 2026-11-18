# spam_score: Jev's "is this advertising?" score (0 to 1) from the background
# spam review, so the dashboard can show why an event was flagged.
# spam_decided_at: when an admin last marked or cleared the event. Only admin
# actions set it, and editing a cleared event resets it, so Event::SpamReview
# only learns from text an admin actually reviewed.
class AddSpamScoreToEvents < ActiveRecord::Migration[8.1]
  def up
    add_column :events, :spam_score, :float
    add_column :events, :spam_decided_at, :datetime
    execute "UPDATE events SET spam_decided_at = spam_at WHERE spam_source = 'operator'"
    execute "UPDATE events SET spam_decided_at = updated_at WHERE spam_source = 'cleared'"
  end

  def down
    remove_column :events, :spam_decided_at
    remove_column :events, :spam_score
  end
end
