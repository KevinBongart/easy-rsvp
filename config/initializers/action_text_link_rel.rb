# Links in event descriptions are written by anonymous visitors. Render them
# as nofollow/ugc so the site passes no search ranking to them.
Rails.application.config.to_prepare do
  ActionText::ContentHelper.scrubber = UserContentLinkScrubber.for_action_text
end
