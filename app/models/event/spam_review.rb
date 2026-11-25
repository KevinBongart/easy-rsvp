require "net/http"

# Asks TypeSafe's Jev model whether an event page is advertising.
#
# Jev cannot be fine-tuned, so the admin's decisions teach it in context: every
# request carries the events the admin most recently cleared with "Not spam" and
# most recently marked as spam. A "Not spam" click therefore lowers the score of
# similar events from the next request on. Sending both kinds keeps the
# examples from making Jev lenient across the board. Examples are ordered by
# spam_decided_at, which only admin actions set and which editing a cleared
# event resets, so organizers cannot put their own text into other reviews.
# Unpublished events are never sent as examples.
#
# Text leaves the app masked: links become "[link to domain]", and email
# addresses, phone numbers and street addresses are replaced with placeholders.
class Event::SpamReview
  API_KEY_VARIABLE = "TYPESAFE_API_KEY"
  URL = URI("https://api.typesafe.ai/v1/systemone")
  THRESHOLD = 0.9
  EXAMPLES_PER_KIND = 10
  EXAMPLE_LENGTH = 400
  MAX_TITLE = 300
  MAX_DESCRIPTION = 12_000
  QUESTION = "Is this an advertisement, affiliate or SEO article, coupon, promo or referral code " \
             "listing, or other promotion of a product, service, website or app, rather than an " \
             "invitation to an event?".freeze

  STREET_WORDS = "street|st|avenue|ave|road|rd|boulevard|blvd|lane|ln|drive|dr|way|court|ct|place|pl|" \
                 "straße|strasse|str|weg|gasse|platz|rue|via|calle|carrer|avenida|ulica|ul"
  # Every repetition is bounded: masking runs on untrusted text, and an
  # unbounded run lets a long page hit Regexp.timeout.
  STREET = /\b\d{1,5}[a-z]?\s+(?:[\p{L}.'-]{1,40}\s){0,3}(?:#{STREET_WORDS})\b\.?/i
  STREET_NAME_FIRST = /\b(?:[\p{L}'-]{0,40}(?:straße|strasse|str\.|straat|weg|gasse|platz)|(?:rue|via|calle|carrer|avenida|ulica|ul\.)(?:\s[\p{L}.'-]{1,40}){1,3})\s?\d{1,5}[a-z]?\b/i
  URL_WITH_SCHEME = %r{https?://(?:[^/\s"'<>@]{0,100}@)?([^/\s"'<>:?#]{1,100})[^\s"'<>]*}i
  URL_WITHOUT_SCHEME = %r{\b(?:www\.)?((?:[a-z0-9-]{1,63}\.){1,5}[a-z]{2,20})(?:/[^\s"'<>]*|\?[^\s"'<>]*)}i
  WWW_HOST = /\bwww\.((?:[a-z0-9-]{1,63}\.){1,5}[a-z]{2,20})\b/i
  EMAIL = /[\w.+-]+@[\w-]+\.[\w.-]+/
  PHONE = /\+?\d[\d\s().-]{5,30}\d/
  # Dates and time ranges look like phone numbers; keep them, they matter.
  NOT_A_PHONE = /\A(?:\d{4}-\d{2}-\d{2}\b|\d{1,2}[.:]\d{2}\s?[-–]\s?\d{1,2}[.:]\d{2}\z)/
  UK_POSTCODE = /\b[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}\b/

  # TypeSafe does not document its error statuses; these are their standard
  # HTTP meanings, shown on the admin dashboard to point at the likely fix.
  HTTP_FAILURE_HINTS = {
    "401" => "API key rejected",
    "402" => "payment required: probably out of credits",
    "403" => "API key rejected",
    "429" => "rate limited"
  }.freeze

  class Error < StandardError; end

  def self.enabled?
    ENV[API_KEY_VARIABLE].present?
  end

  # Only production must review every event; elsewhere a missing key is normal.
  def self.required?
    Rails.configuration.x.spam_review_required.present?
  end

  def self.missing_required_key?
    required? && !enabled?
  end

  def initialize(event)
    @event = event
  end

  # Jev's 0-1 score, or nil when the review is disabled or anything fails.
  def score(page: self.page)
    return unless self.class.enabled?

    score = ask(page)
    record_success if score
    score
  end

  # What Jev is shown. Truncates before masking so masking time stays bounded.
  def page
    { title: mask(event.title.to_s[0, MAX_TITLE]), description: mask(visible_text(event.rich_text_body&.body&.to_html.to_s)[0, MAX_DESCRIPTION]) }
  end

  private

  attr_reader :event

  # Only the API call is rescued here, so an error recording Jev's status
  # cannot pass for a Jev failure or discard a valid score.
  def ask(page)
    response = post(state: page, questions: { advertising: { type: "noul", instructions: } })
    score = Float(response.dig("answers", "advertising", "noul")) if response.is_a?(Hash) && response["answers"].is_a?(Hash)
    raise Error, "unexpected answer #{score.inspect}" unless score&.between?(0, 1)

    score
  rescue StandardError => e
    record_failure(e)
    nil
  end

  # Status bookkeeping must not change the moderation result.
  def record_success
    SpamReviewStatus.record_success!
  rescue StandardError => e
    Rails.error.report(e, handled: true)
  end

  # Notifies once when Jev starts failing rather than for every event: an
  # outage would otherwise send one notice per event created. The dashboard
  # shows the streak and its latest error.
  def record_failure(error)
    started_failing = SpamReviewStatus.record_failure!(failure_summary(error))
    Rails.error.report(error, handled: true, context: { event_id: event.id }) if started_failing
  rescue StandardError => status_error
    # Without the status there is no telling whether a streak started, so
    # report Jev's error rather than risk missing an outage.
    Rails.error.report(error, handled: true, context: { event_id: event.id })
    Rails.error.report(status_error, handled: true)
  end

  # Only messages this class wrote are kept: other exceptions' messages can
  # quote the response or the event text.
  def failure_summary(error)
    error.is_a?(Error) ? "#{error.class.name}: #{error.message}" : error.class.name
  end

  def instructions
    cleared = examples(Event.spam_source_cleared.where(published: true))
    marked = examples(Event.spam_source_operator)
    text = +QUESTION
    if cleared.any?
      text << "\n\nThe site's administrator reviewed these pages and confirmed they are genuine event pages, not advertising:\n"
      text << cleared.join("\n")
    end
    if marked.any?
      text << "\n\nThe administrator confirmed these pages are advertising spam:\n"
      text << marked.join("\n")
    end
    text
  end

  def examples(scope)
    scope.where.not(spam_decided_at: nil).where.not(id: event.id)
         .order(spam_decided_at: :desc, id: :desc).limit(EXAMPLES_PER_KIND)
         .includes(:rich_text_body).map do |example_event|
      example = self.class.new(example_event).page
      "- Title: #{example[:title].squish}\n  Description: #{example[:description].squish[0, EXAMPLE_LENGTH]}"
    end
  end

  # The text guests see (Event::SpamCheck decides what that is, including the
  # HTML of content attachments), plus where each link points: the target
  # domain is a strong spam signal that anchor text like "click here" hides.
  def visible_text(html)
    fragment = Nokogiri::HTML4.fragment(Event::SpamCheck.readable_html(html))
    fragment.css("a[href]").each do |link|
      host = link["href"].to_s[URL_WITH_SCHEME, 1]
      link.add_next_sibling(Nokogiri::XML::Text.new(" (link to #{host.downcase.delete_prefix('www.')})", fragment.document)) if host && !link.text.include?(host)
    end
    Event::SpamCheck.visible_text(fragment.to_html)
  end

  def mask(text)
    text.gsub(URL_WITH_SCHEME) { "[link to #{Regexp.last_match(1).downcase.delete_prefix('www.')}]" }
        .gsub(EMAIL, "[email]")
        .gsub(URL_WITHOUT_SCHEME) { "[link to #{Regexp.last_match(1).downcase.delete_prefix('www.')}]" }
        .gsub(WWW_HOST) { "[link to #{Regexp.last_match(1).downcase}]" }
        .gsub(PHONE) { |match| match.match?(NOT_A_PHONE) ? match : "[phone]" }
        .gsub(STREET, "[address]")
        .gsub(STREET_NAME_FIRST, "[address]")
        .gsub(UK_POSTCODE, "[postcode]")
  end

  def post(body)
    request = Net::HTTP::Post.new(URL, "Authorization" => "Bearer #{api_key}", "Content-Type" => "application/json")
    response = Net::HTTP.start(URL.host, URL.port, use_ssl: true, open_timeout: 5, read_timeout: 20, write_timeout: 10) do |http|
      http.request(request, { model: "jev-latest" }.merge(body).to_json)
    end
    raise Error, http_failure(response) unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  def http_failure(response)
    hint = HTTP_FAILURE_HINTS[response.code]
    hint ? "TypeSafe answered HTTP #{response.code} (#{hint})" : "TypeSafe answered HTTP #{response.code}"
  end

  def api_key
    ENV[API_KEY_VARIABLE]
  end
end
