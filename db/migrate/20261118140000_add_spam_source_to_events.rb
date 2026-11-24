# Records who marked an event as spam. "operator" marks (the spam-wave
# migrations) are final. "automatic" marks come from Event::SpamCheck when an
# event is saved; editing the event re-runs the check and can clear them.
class AddSpamSourceToEvents < ActiveRecord::Migration[8.1]
  def up
    add_column :events, :spam_source, :string
    execute "UPDATE events SET spam_source = 'operator' WHERE spam_at IS NOT NULL"
    add_check_constraint :events,
      "(spam_at IS NULL AND spam_source IS NULL) OR (spam_at IS NOT NULL AND spam_source IN ('operator', 'automatic'))",
      name: "events_spam_source_matches_spam_at"
  end

  def down
    remove_check_constraint :events, name: "events_spam_source_matches_spam_at"
    remove_column :events, :spam_source
  end
end
