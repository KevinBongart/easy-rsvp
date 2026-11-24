# "cleared" records an operator's decision that an event is not spam, so the
# save-time spam check stops flagging it.
class AllowClearedSpamSource < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :events, name: "events_spam_source_matches_spam_at"
    add_check_constraint :events,
      "(spam_at IS NULL AND (spam_source IS NULL OR spam_source = 'cleared')) OR (spam_at IS NOT NULL AND spam_source IN ('operator', 'automatic'))",
      name: "events_spam_source_matches_spam_at"
  end

  def down
    execute "UPDATE events SET spam_source = NULL WHERE spam_source = 'cleared'"
    remove_check_constraint :events, name: "events_spam_source_matches_spam_at"
    add_check_constraint :events,
      "(spam_at IS NULL AND spam_source IS NULL) OR (spam_at IS NOT NULL AND spam_source IN ('operator', 'automatic'))",
      name: "events_spam_source_matches_spam_at"
  end
end
