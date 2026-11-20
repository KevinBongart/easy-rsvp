require "cgi"

# Decides whether an event's title or description looks like SEO spam. Runs on
# every save that changes either one, so brand-new events (which never have
# RSVPs) and later edits are both covered.
#
# Tuned on the November 2026 production snapshot: it catches 99.85% of the
# 6,064 events marked during the spam wave and flags none of the 11,380 others
# except 2022 security-scanner probes and two test posts. A flagged organizer
# can edit the event; the check runs again on save. Event#confidently_spam?
# decides whether they are told.
#
# Each rule has a name so failures can be explained and tested. Prefer
# structural signals (obfuscation, amounts next to codes, body shape) over
# topic keywords; topic words only count with a second signal.
class Event::SpamCheck
  MAX_TITLE_LENGTH = 2_000 # caps regex work; real titles stay well below
  LONG_TEXT = 3_500
  VERY_LONG_TEXT = 6_000

  # ---------------------------------------------------------------- title --
  FANCY_LETTERS = /[\u{1D400}-\u{1D7FF}]/
  # 【】『』〔〕 are left out: Japanese and Chinese titles use them normally.
  DECORATIVE_BRACKETS = /[〖〗⦃⦄꧁꧂⟦⟧〘〙]/
  CODE_WRAPPER = /\{\[\^|\[\[|\{\{|\(\(|<</
  CJK_WRAPPED_CODE = /[【〔『]\s*(?=[A-Za-z0-9_-]*\d)(?=[A-Za-z0-9_-]*[A-Za-z])[A-Za-z0-9_-]{4,}\s*[】〕』]/

  AMOUNT = Regexp.union(/\d ?%|%\s?\d/, /[$€£₹¥]\s?\d|\d[\d.,]*\s?(€|\$|£|zł|usd|eur|gbp)(?!\p{L})/i)
  # Upper case, 4+ characters, at least one digit and one letter: PEP25, NEX55.
  CODE_TOKEN = /(?<![\p{L}\d])(?=[A-Z0-9_-]*\d)(?=[A-Z0-9_-]*[A-Z])[A-Z0-9][A-Z0-9_-]{3,}(?![\p{L}\d])/

  PROMO_PHRASE = /\b(promo|discount|coupon|referral|refferal|voucher|bonus|invite|partner) ?codes?\b|\bcodes? (promo|r[ée]duction|sconto|descuento|desconto)\b|rabatt?code|rabattkod|rabatkode|kod rabatow\w*|kod promocyjny|gutscheincode|kortingscode|codice sconto|c[oó]digo (de )?(desconto|descuento|promo\w*)|cupom de desconto|cup[oó]n de descuento|промокод|код знижки|优惠码|كود خصم/i
  COMMERCE_WORD = /\b(coupons?|vouchers?|referral|refferal|promo|promocode|codes?|kod|c[oó]digo|codice|rabatt\w*|gutschein\w*|cupom|cup[oó]n\w*|descuento|kupong\w*)\b|промокод|скидк|знижк|优惠|クーポン|خصم/i
  PRICE_CUT = /\b(off|menos|mniej|taniej|korting|sparen|savings?|save|économisez|réduction|desconto|descuento|zniżk\w*)\b/i
  NOT_PROMO = /dress[ -]?code|code of conduct|qr ?code|gate code|door code/i

  # Social media handles used as titles by follower-seekers: a leading _, a run
  # of underscores, or an @handle containing a digit, _ or . (so venue titles
  # like "@home" and "@Starbucks" pass).
  SOCIAL_HANDLE = /\A(?=[\w.@]*[a-z])(?:_[\w.]{3,}|@(?=[\w.]*[\d_.])[\w.]{3,}|[\w.]*__[\w.]*)\z/i

  PHONE = /\d{3}[^\p{L}\d]{0,5}\d{3}[^\p{L}\d]{0,5}\d{4}/
  PHONE_CONTEXT = /customer (service|support|care)|\bsupport\b|helpline|hotline|\btoll|airlines?|airways|\bflights?\b|\bbooking\b|reservations?|refund|live (person|agent)|📞|☎/i
  TOLL_FREE = /(?<!\d)1?\W{0,4}8(00|33|44|55|66|77|88)\W{1,5}\d{3}\W{1,5}\d{4}(?!\d)/

  # Phrases that are spam on their own.
  STRONG_PHRASES = {
    review_bait: /reviews?.{0,6}(&|and) complaints|consumer reports|reviews? \(?20\d\d|\breviews? (100%|scam|legit|exposed)|scam or legit|is it legit|does it (really )?work|we tried it/i,
    pharmacy: /\bno rx\b|\bbuy \w+ online\b|without prescription/i,
    account_viewer: /\b(private|story|profile|account) viewer\b/i,
    followers: /\bfree [\w ]{0,15}followers\b|\bfollowers? (free|badha|increase|hack)/i,
    gambling: /\brobux\b|\bspoof(er|ing)\b|\bfree spins\b|\bno deposit\b|\b(bitcoin|crypto|online|new|best) casinos?\b|\bgambling sites\b|\bonline pokies\b|\bbetting sites\b/i,
    adult_drugs: /\b(xvideos|xnxx|xhamster|pornhub|porn|nsfw|hentai|onlyfans|adderall|lorazepam|tramadol|xanax|viagra|cialis|oxycodone)\b/i,
    clickbait_video: /\b(leak\w*|sex|xxx|xem|18\+)\b.{0,25}\b(clips?|videos?)\b|\bclip\W{1,3}video\b|\b(clips?|videos?)\b.{0,25}\b(leak\w*|xxx)\b|\bfull (hd )?clip\b|clip n[oó]ng/i,
    airline_support: /missed (your )?\w+ flight|miss a \w+ flight|name correction|contatti telefonici|flight (change|cancell?ation) (policy|number)/i,
    # Prefix match: spammers glue words on ("iPTVServices").
    iptv: /\biptv/i,
    free_game_currency: /\bfree (robux|v-?bucks|gift ?cards?|eshop|psn|diamonds|gems)\b/i
  }.freeze

  # Topics that are fine in real events ("Casino night", "Customer service
  # team lunch") and only count together with a sales word or phone number.
  WEAK_TOPIC = /\b(peptides?|casinos?|followers|customer (service|support|care)|helpline|toll.?free|support number|gummies|keto|weight loss|crypto|bitcoin|forex|betting|slots?|cheats?|mod apk|apk)\b/i
  WEAK_TOPIC_SECOND = /\b(best|top \d+|buy|cheap|reviews?|legit|scam|trial|online|price|pricing|order|discount|coupon|promo|bonus|guide|provider|subscription|generator|unlimited|working|official|number)\b/i

  # ----------------------------------------------------------------- body --
  # Tags the Trix editor produces. Spam scripts post raw HTML with <p>, <h2>,
  # <table> and so on. Remove this rule if the app switches editors.
  EDITOR_TAGS = %w[div br strong em a ul ol li h1 blockquote pre del figure img figcaption
                   action-text-attachment span].freeze

  def self.spam?(title:, html:)
    reasons(title: title, html: html).any?
  end

  def self.reasons(title:, html:)
    new(title, html).reasons
  end

  # The description's text as guests read it, whitespace collapsed; image
  # payloads do not count. Also used for Event's description length limit.
  def self.visible_text(html)
    new("", html).visible_text
  end

  def initialize(title, html)
    @title = title.to_s[0, MAX_TITLE_LENGTH].gsub(/[[:space:]]+/, " ")
    @html = html.to_s
  end

  def reasons
    title_reasons + body_reasons
  end

  def visible_text
    raw_text.gsub(/[[:space:]]+/, " ").strip
  end

  private

  attr_reader :title, :html

  def title_reasons
    reasons = []
    reasons << :fancy_letters if title.match?(FANCY_LETTERS)
    reasons << :decorative_brackets if title.match?(DECORATIVE_BRACKETS)
    reasons << :social_handle if title.strip.match?(SOCIAL_HANDLE)
    reasons << :code_wrapper if title.match?(CODE_WRAPPER) || title.match?(CJK_WRAPPED_CODE)
    reasons << :promo_code if title.match?(PROMO_PHRASE)
    if !title.match?(NOT_PROMO) && title.match?(COMMERCE_WORD) && (title.match?(AMOUNT) || title.match?(CODE_TOKEN))
      reasons << :offer_amount
    end
    reasons << :price_cut_code if title.match?(AMOUNT) && title.match?(PRICE_CUT) && title.match?(CODE_TOKEN)
    reasons << :call_center_phone if title.match?(PHONE) && (title.match?(PHONE_CONTEXT) || title.match?(TOLL_FREE))
    STRONG_PHRASES.each { |name, pattern| reasons << name if title.match?(pattern) }
    if title.match?(WEAK_TOPIC) && (title.match?(WEAK_TOPIC_SECOND) || title.match?(PHONE))
      reasons << :weak_topic_corroborated
    end
    reasons
  end

  def body_reasons
    return [] if html.empty?

    readable = readable_html
    reasons = []
    tags = readable.scan(/<([a-z][a-z0-9-]*)/i).flatten.map(&:downcase).uniq
    reasons << :non_editor_html if (tags - EDITOR_TAGS).any?

    text = visible_text
    links = readable.scan(/<a\b[^>]*\bhref=/i).size
    reasons << :very_long_text if text.size >= VERY_LONG_TEXT
    reasons << :long_text_with_link if text.size >= LONG_TEXT && links >= 1

    lines = raw_text.split("\n").map { |line| line.gsub(/[[:space:]]+/, " ").strip.downcase }.select { |line| line.size >= 30 }
    reasons << :repeated_lines if (lines.tally.values.max || 0) >= 3
    reasons
  end

  def raw_text
    @raw_text ||= Nokogiri::HTML4.fragment(readable_html.gsub(%r{<(br|/div|/li|/h1|/blockquote|/pre|/figcaption)\b[^>]*>}i, "\n\\0")).text
  end

  # The body as guests read it, minus image payloads. Images and data: URIs
  # are dropped so photo-heavy invitations do not count as long. Everything
  # Action Text renders stays in: text inside <figure>, captions, and the HTML
  # of content attachments (stored escaped in their content= attribute), so
  # spam cannot hide inside them. HTML4 parsing has no tree-depth limit, unlike
  # HTML5, so deeply nested input cannot raise.
  def readable_html
    @readable_html ||= html.gsub(/data:[^"'\s)]+/, "")
      .gsub(/<img\b[^>]*>/i, " ")
      .gsub(/<action-text-attachment\b([^>]*)>/i) { " #{attachment_markup(Regexp.last_match(1))} " }
  end

  def attachment_markup(attributes)
    %w[content caption].filter_map do |name|
      match = attributes.match(/\b#{name}=(?:"([^"]*)"|'([^']*)')/i)
      CGI.unescapeHTML(match[1] || match[2]) if match
    end.join(" ")
  end
end
