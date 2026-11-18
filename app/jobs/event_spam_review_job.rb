# Second opinion for events the Ruby rules let through. Runs after the save so
# creating an event never waits on TypeSafe, and fails open: any API error
# leaves the event up.
class EventSpamReviewJob < ApplicationJob
  def perform(event_id)
    event = Event.find_by(id: event_id)
    return unless event&.spam_review_needed?

    page = Event::SpamReview.page(event)
    score = Event::SpamReview.score(event, page:)
    return if score.nil?

    changes = { spam_score: score }
    changes.merge!(spam_at: Time.current, spam_source: "automatic") if score >= Event::SpamReview::THRESHOLD
    # Write only if Jev judged the text the event still has and no admin has
    # decided meanwhile. A text edit queued its own review; other edits (date,
    # publication) do not change the answer.
    event.with_lock do
      event.update_columns(changes) if event.spam_review_needed? && Event::SpamReview.page(event) == page
    end
  end
end
