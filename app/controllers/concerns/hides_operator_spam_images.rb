# Prepended to Active Storage's blob and representation controllers (see
# config/initializers/spam_images.rb) so images embedded only in events an
# operator marked as spam answer 404. The check is part of the signed-id blob
# lookup itself: one indexed query, no extra request work for normal images.
# Automatic marks keep their images, since those organizers still see their
# pages, and an admin preview session still sees everything.
module HidesOperatorSpamImages
  private

  def blob_scope
    return super if AdminPreview.active?(session)

    super.where.not(Event::SpamImages::HIDDEN_BLOB)
  end
end
