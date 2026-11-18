require "net/http"

# Asks TypeSafe's Jev model whether an event page is advertising.
#
# Jev cannot be fine-tuned, so the admin's decisions teach it in context: every
# request carries the most recent events the admin cleared with "Not spam" and
# the most recent ones the admin marked as spam. A "Not spam" click therefore
# lowers the score of similar events from the next request on. Sending both
# kinds keeps the examples from making Jev lenient across the board.
#
# Text leaves the app masked: links become "[link to domain]", and email
# addresses, phone numbers and street addresses are replaced with placeholders.
module Event::SpamReview
  URL = URI("https://api.typesafe.ai/v1/systemone")
  THRESHOLD = 0.9
  EXAMPLES_PER_KIND = 10
  EXAMPLE_LENGTH = 400
  MAX_TITLE = 300
  MAX_DESCRIPTION = 3000
  QUESTION = "Is this an advertisement, affiliate or SEO article, coupon, promo or referral code " \
             "listing, or other promotion of a product, service, website or app, rather than an " \
             "invitation to an event?".freeze
  STREET = /\b\d{1,5}[a-z]?\s+(?:[\p{L}.'-]+\s){0,3}(?:street|st|avenue|ave|road|rd|boulevard|blvd|lane|ln|drive|dr|way|court|ct|place|pl|straße|strasse|str|weg|gasse|platz|rue|via|calle|carrer|ulica|ul)\b\.?/i

  class Error < StandardError; end

  module_function

  def enabled?
    api_key.present?
  end

  # Jev's 0-1 score, or nil when the review is disabled or the API fails.
  def score(event)
    return unless enabled?

    response = post(state: page(event), questions: { advertising: { type: "noul", instructions: instructions(except: event) } })
    Float(response.dig("answers", "advertising", "noul"))
  rescue Error, JSON::ParserError, TypeError, ArgumentError, Net::OpenTimeout, Net::ReadTimeout, SystemCallError, OpenSSL::SSL::SSLError, IOError => e
    Rails.error.report(e, handled: true, context: { event_id: event.id })
    nil
  end

  def instructions(except:)
    cleared = examples(Event.where(spam_source: "cleared"), except)
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
    scope.where.not(id: except.id).order(updated_at: :desc, id: :desc).limit(EXAMPLES_PER_KIND)
         .includes(:rich_text_body).map do |event|
      example = page(event)
      "- Title: #{example[:title].squish}\n  Description: #{example[:description].squish[0, EXAMPLE_LENGTH]}"
    end
  end

  def page(event)
    { title: mask(event.title.to_s)[0, MAX_TITLE], description: mask(visible_text(event.rich_text_body&.body&.to_html.to_s))[0, MAX_DESCRIPTION] }
  end

  def visible_text(html)
    html = html.gsub(/data:[^"'\s)]+/, "").gsub(%r{<(br|/div|/li|/h\d|/p)\b[^>]*>}i, "\n\\0")
    Nokogiri::HTML4.fragment(html).text.gsub(/[ \t]+/, " ").gsub(/\n{3,}/, "\n\n").strip
  end

  def mask(text)
    text.gsub(%r{https?://([^/\s"'<>]+)[^\s"'<>]*}i) { "[link to #{Regexp.last_match(1).downcase.delete_prefix('www.')}]" }
        .gsub(/[\w.+-]+@[\w-]+\.[\w.-]+/, "[email]")
        .gsub(/\+?\d[\d\s().-]{7,}\d/, "[phone]")
        .gsub(STREET, "[address]")
  end

  def post(body)
    request = Net::HTTP::Post.new(URL, "Authorization" => "Bearer #{api_key}", "Content-Type" => "application/json")
    response = Net::HTTP.start(URL.host, URL.port, use_ssl: true, open_timeout: 5, read_timeout: 20) do |http|
      http.request(request, { model: "jev-latest" }.merge(body).to_json)
    end
    raise Error, "TypeSafe answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  def api_key
    ENV["TYPESAFE_API_KEY"]
  end
end
