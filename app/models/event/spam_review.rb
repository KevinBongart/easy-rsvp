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
module Event::SpamReview
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
  STREET = /\b\d{1,5}[a-z]?\s+(?:[\p{L}.'-]+\s){0,3}(?:#{STREET_WORDS})\b\.?/i
  STREET_NAME_FIRST = /\b(?:[\p{L}'-]*(?:straße|strasse|str\.|weg|gasse|platz)|(?:rue|via|calle|carrer|avenida|ulica|ul\.)(?:\s+[\p{L}.'-]+){1,3})\s*\d{1,5}[a-z]?\b/i
  URL_WITH_SCHEME = %r{https?://(?:[^/\s"'<>@]*@)?([^/\s"'<>:?#]+)[^\s"'<>]*}i
  URL_WITHOUT_SCHEME = %r{\b(?:www\.)?((?:[a-z0-9-]+\.)+[a-z]{2,})(?:/[^\s"'<>]*|\?[^\s"'<>]*)}i
  WWW_HOST = /\bwww\.((?:[a-z0-9-]+\.)+[a-z]{2,})\b/i
  EMAIL = /[\w.+-]+@[\w-]+\.[\w.-]+/
  ISO_DATE = /\A\d{4}-\d{2}-\d{2}\z/
  PHONE = /\+?\d[\d\s().-]{5,}\d/
  UK_POSTCODE = /\b[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}\b/

  class Error < StandardError; end

  module_function

  def enabled?
    api_key.present?
  end

  # Jev's 0-1 score, or nil when the review is disabled or anything fails.
  def score(event, page: page(event))
    return unless enabled?

    response = post(state: page, questions: { advertising: { type: "noul", instructions: instructions(except: event) } })
    score = Float(response.dig("answers", "advertising", "noul")) if response.is_a?(Hash) && response["answers"].is_a?(Hash)
    raise Error, "unexpected answer #{score.inspect}" unless score&.between?(0, 1)

    score
  rescue StandardError => e
    Rails.error.report(e, handled: true, context: { event_id: event.id })
    nil
  end

  def instructions(except:)
    cleared = examples(Event.where(spam_source: "cleared", published: true), except)
    marked = examples(Event.where(spam_source: "operator"), except)
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

  def examples(scope, except)
    scope.where.not(spam_decided_at: nil).where.not(id: except.id)
         .order(spam_decided_at: :desc, id: :desc).limit(EXAMPLES_PER_KIND)
         .includes(:rich_text_body).map do |event|
      example = page(event)
      "- Title: #{example[:title].squish}\n  Description: #{example[:description].squish[0, EXAMPLE_LENGTH]}"
    end
  end

  def page(event)
    { title: mask(event.title.to_s)[0, MAX_TITLE], description: mask(visible_text(event.rich_text_body&.body&.to_html.to_s))[0, MAX_DESCRIPTION] }
  end

  # The text guests see, plus where each link points: the target domain is a
  # strong spam signal that anchor text like "click here" hides.
  def visible_text(html)
    fragment = Nokogiri::HTML4.fragment(html.gsub(/data:[^"'\s)]+/, "").gsub(%r{<(br|/div|/li|/h\d|/p)\b[^>]*>}i, "\n\\0"))
    fragment.css("a[href]").each do |link|
      host = link["href"].to_s[URL_WITH_SCHEME, 1]
      link.add_next_sibling(Nokogiri::XML::Text.new(" (link to #{host.downcase.delete_prefix('www.')})", fragment.document)) if host && !link.text.include?(host)
    end
    fragment.text.gsub(/[ \t]+/, " ").gsub(/\n{3,}/, "\n\n").strip
  end

  def mask(text)
    text.gsub(URL_WITH_SCHEME) { "[link to #{Regexp.last_match(1).downcase.delete_prefix('www.')}]" }
        .gsub(EMAIL, "[email]")
        .gsub(URL_WITHOUT_SCHEME) { "[link to #{Regexp.last_match(1).downcase.delete_prefix('www.')}]" }
        .gsub(WWW_HOST) { "[link to #{Regexp.last_match(1).downcase}]" }
        .gsub(PHONE) { |match| match.match?(ISO_DATE) ? match : "[phone]" }
        .gsub(STREET, "[address]")
        .gsub(STREET_NAME_FIRST, "[address]")
        .gsub(UK_POSTCODE, "[postcode]")
  end

  def post(body)
    request = Net::HTTP::Post.new(URL, "Authorization" => "Bearer #{api_key}", "Content-Type" => "application/json")
    response = Net::HTTP.start(URL.host, URL.port, use_ssl: true, open_timeout: 5, read_timeout: 20, write_timeout: 10) do |http|
      http.request(request, { model: "jev-latest" }.merge(body).to_json)
    end
    raise Error, "TypeSafe answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  def api_key
    ENV["TYPESAFE_API_KEY"]
  end
end
