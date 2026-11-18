# Second opinion for events the Ruby rules let through. Runs after the save so
# creating an event never waits on TypeSafe, and fails open: any API error
# leaves the event up.
class EventSpamReviewJob < ApplicationJob
  def perform(event_id)
    event = Event.find_by(id: event_id)
    return unless event&.spam_review_needed?

    score = Event::SpamReview.score(event)
    return if score.nil?

    changes = { spam_score: score }
    changes.merge!(spam_at: Time.current, spam_source: "automatic") if score >= Event::SpamReview::THRESHOLD
    # Skip the write if the organizer edited the event (its rich text touches
    # updated_at) or an admin decided on it while Jev was answering; the edit
    # queued its own review.
    Event.where(id: event.id, updated_at: event.updated_at, spam_source: nil).update_all(changes)
  end
end
