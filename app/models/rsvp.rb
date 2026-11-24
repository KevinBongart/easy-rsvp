class Rsvp < ApplicationRecord
  include Hashid::Rails

  RESPONSES = [
    :yes,
    :maybe,
    :no
  ]

  # Legitimate names (2026-11-20 snapshot): median 12 characters, p99.9 80;
  # 50 of ~98,000 exceed 200, 44 of them in one event. Like Event's title
  # limit, only a change that makes a name longer than before is refused, so
  # older long names stay editable.
  MAXIMUM_NAME_LENGTH = 200
  # Links: a scheme, "www.", or a domain (with any subdomains) on a generic
  # TLD spammers favor or on .ru, .cn, .tk, .io, or .ly. Email addresses and
  # other country domains pass: guests sign with their email (70 legitimate
  # names on the snapshot) or their organization ("acme.de", "club.org"). No
  # match starts right after "@" or ".", so "a@mail.example.com" is an email,
  # not a link.
  LINK = %r{https?://|\bwww\.|(?<![@\w.-])(?:[\p{L}\d-]+\.)+(com|net|info|biz|io|xyz|top|site|online|shop|store|app|ly|link|click|club|vip|bet|live|pro|ru|cn|tk)\b}i
  # Characters that render as nothing, for names that only look filled in:
  # spaces, format characters such as the zero-width space, and the Hangul
  # fillers.
  INVISIBLE = /[\p{Z}\p{Cf}[:space:]\u115F\u1160\u3164\uFFA0]/
  # Combining marks stacked on one letter. Real scripts use 2 or 3; the
  # longest run in a legitimate name on the snapshot is 13 (decorative
  # "zalgo" text). Longer runs draw a tower of accents over the guest list.
  MAXIMUM_STACKED_MARKS = 15
  STACKED_MARKS = /\p{M}{#{MAXIMUM_STACKED_MARKS + 1},}/

  belongs_to :event

  validates :name, presence: true
  validates :response, presence: true, inclusion: { in: RESPONSES.map(&:to_s) }
  validate :name_visible, if: :will_save_change_to_name?
  validate :name_within_limit, if: :will_save_change_to_name?
  validate :name_is_just_a_name, if: :will_save_change_to_name?

  # Use this to avoid including new (unsaved) records
  scope :persisted, -> { where.not(id: nil) }

  private

  def name_within_limit
    length = name.to_s.length
    return if length <= MAXIMUM_NAME_LENGTH || length <= name_was.to_s.length

    errors.add(:name, :too_long, count: MAXIMUM_NAME_LENGTH)
  end

  # Presence passes names made only of zero-width or filler characters,
  # which the organizer would see as a blank row.
  def name_visible
    return if name.blank? || name.gsub(INVISIBLE, "").present?

    errors.add(:name, :blank)
  end

  # The message does not say which rule matched: the code is public, but
  # spelling it out in the response would make probing even cheaper.
  def name_is_just_a_name
    return unless name_resembles_spam?(name_as_read) || name.to_s.match?(STACKED_MARKS)

    errors.add(:name, :not_just_a_name, message: "should be just your name")
  end

  def name_resembles_spam?(text)
    text.match?(LINK) || Event::SpamCheck.spam_content?(text)
  end

  # The name as the rules should read it: fullwidth letters and dots folded
  # to ASCII (NFKC) and invisible format characters dropped, so "ｃａｓｉｎｏ．ｃｏｍ"
  # and "casino.c\u200Bom" read as "casino.com". Only the check uses it; the
  # name is saved as typed, so emoji and scripts that need zero-width joiners
  # keep them.
  def name_as_read
    name.to_s.unicode_normalize(:nfkc).gsub(/\p{Cf}/, "")
  end
end
