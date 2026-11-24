# Event::SpamCheck only runs when an event is saved, so events created
# between the previous spam pass and this deploy were never checked. Check
# every unmarked event created since the spam wave began, once, and mark
# matches as automatic so their organizers can still edit them.
#
# Unlike the earlier spam migrations, this one deliberately uses the live
# Event::SpamCheck: its marks are reversible by organizers, and it should
# agree with what the app does on save.
class FlagUncheckedSpamEvents < ActiveRecord::Migration[8.1]
  SPAM_WAVE_STARTED_ON = Time.utc(2026, 11, 16)

  class MigrationEvent < ActiveRecord::Base
    self.table_name = "events"
  end

  class MigrationRichText < ActiveRecord::Base
    self.table_name = "action_text_rich_texts"
  end

  def up
    flagged = 0

    MigrationEvent.where(spam_at: nil).where(created_at: SPAM_WAVE_STARTED_ON..).find_each do |event|
      html = MigrationRichText.where(record_type: "Event", record_id: event.id, name: "body").pick(:body).to_s
      next unless Event::SpamCheck.spam?(title: event.title, html: html)

      event.update_columns(spam_at: Time.current, spam_source: "automatic")
      flagged += 1
    end

    say "Flagged #{flagged} unchecked events as automatic spam"
  end

  def down
    # Marks are indistinguishable from later automatic ones; leave them.
  end
end
