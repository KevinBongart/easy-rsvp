# Marks spam that AddSpamAtToEvents could not see: events created after it
# ran in production on 2026-11-18 at 11:32 UTC, plus a few earlier ones its
# classifier missed.
#
# Two parts, both limited to events created since the wave began and not
# already marked:
#
# 1. REVIEWED_SPAM_IDS were read one by one in a production snapshot taken on
#    2026-11-18 at 11:36 UTC. Most are SEO pages the classifier missed because
#    visitors arriving from search had RSVPed (the "free followers" pages had
#    up to 46 RSVPs), because the title used Unicode math letters, or because
#    the topic was new (Robux, Pokemon GO spoofing, game dice links). The rest
#    are spam-tool test posts and follower requests typed in by visitors who
#    landed on spam pages.
# 2. The original classifier reruns with extra title patterns for those new
#    topics, catching spam created after the snapshot. On the snapshot it marks
#    every post-deploy spam event and no legitimate event.
#
# The rules are frozen here so later application changes cannot change what
# this migration did.
class MarkMoreSpamEvents < ActiveRecord::Migration[8.1]
  SPAM_WAVE_STARTED_ON = "2026-11-16"

  REVIEWED_SPAM_IDS = [
    12520, # "Creator Tools and Affiliate Program Research Session" (product promotion)
    14579, # Shein promo code written in Unicode math letters
    15337, 15496, 15526, # "Tool test ... safe to ignore" spam-tool test posts
    17382, 17403, # "Free Instagram/TikTok Followers" SEO pages with RSVPs from search visitors
    17398, # Instagram hashtag spam
    17536, 17572, 17578, 17600, 17680, # follower requests from visitors of spam pages
    17553, # Pokemon GO spoofer
    17558, # Monopoly Go dice links
    17577, # "Free tv"
    17581, # Robux generator
    17642, # Google Play redeem code generator
    17699 # crochet affiliate SEO page
  ].freeze

  MARK_REVIEWED_SQL = <<~SQL
    UPDATE events
    SET spam_at = CURRENT_TIMESTAMP
    WHERE id IN (:ids)
      AND created_at >= :since
      AND spam_at IS NULL
  SQL

  MARK_CLASSIFIED_SQL = <<~'SQL'
    WITH candidates AS (
      SELECT
        events.id,
        events.title,
        COALESCE(bodies.body, '') AS body,
        LENGTH(COALESCE(bodies.body, '')) AS body_length,
        COALESCE(ARRAY_LENGTH(REGEXP_SPLIT_TO_ARRAY(bodies.body, 'href='), 1) - 1, 0) AS link_count,
        (SELECT COUNT(*) FROM rsvps WHERE rsvps.event_id = events.id) AS rsvp_count
      FROM events
      LEFT JOIN action_text_rich_texts AS bodies
        ON bodies.record_type = 'Event'
        AND bodies.record_id = events.id
        AND bodies.name = 'body'
      WHERE events.created_at >= :since
        AND events.spam_at IS NULL
    ),
    signals AS (
      SELECT
        candidates.id,
        candidates.rsvp_count,
        (
          title ~* '(coupon|discount|voucher|referral|refferal|rabatt|rabatowy|polecaj|sconto|kortingscode|cupom|cup[oó]n|descuento|gutschein|\mpromo\M|promo ?codes?|promotional (code|discount)|partner code|sign ?up bonus|welcome bonus|bonus code|\mkod |c[oó]digo |code [\[\(\{"“])'
          OR title ~* '\d{1,3} ?% ?(off|taniej|di sconto|de r[ée]duction|en |savings)'
          OR title ~* '\m(iptv|peptides?|casino|xvideos|porn|nsfw|hentai|adderall|lorazepam|codeine|tramadol|xanax|viagra|onlyfans)\M'
          OR title ~* '(reviews?.{0,6}(&|and) complaints|consumer reports|honest (review|experience)|reviews? 20\d\d|full ?\.?movie|full clip|downl.?ad|no rx|buy \w+ online|private viewer|story viewer|free \w+ followers|customer (service|support|care)|helpline|toll.?free|contatti telefonici|missed (your )?\w+ flight|miss a \w+ flight|name correction)'
          OR title ~* '(\mfollowers\M|\mrobux\M|\mspoof(er|ing)?\M|redeem codes?|dice links|free spins|no deposit|(bitcoin|crypto) casinos?|gambling sites)'
          OR title ~ '\d{3}\D{0,8}\d{3}\D{0,8}\d{4}'
          OR title ~ '[〖〗【】『』⦃⦄꧁꧂⟦⟧〘〙〔〕]'
          OR title ~ '[\U0001D400-\U0001D7FF]'
          OR title ~ '\{\[\^|\[\[|\{\{|\(\(|<<'
        ) AS spam_title,
        (body_length >= 4500 AND link_count >= 2) AS long_body_with_links,
        (body_length >= 6000 AND rsvp_count = 0) AS long_body_without_rsvps,
        (body ~* 'href="https?://[^"]*(adultimes\.online|latest-news2026\.blogspot)') AS known_spam_domain
      FROM candidates
    )
    UPDATE events
    SET spam_at = CURRENT_TIMESTAMP
    FROM signals
    WHERE events.id = signals.id
      AND (
        ((signals.spam_title OR signals.long_body_with_links) AND signals.rsvp_count <= 4)
        OR signals.long_body_without_rsvps
        OR (signals.known_spam_domain AND signals.rsvp_count <= 4)
      )
  SQL

  def up
    reviewed = exec_update(
      sanitize([ MARK_REVIEWED_SQL, { ids: REVIEWED_SPAM_IDS, since: SPAM_WAVE_STARTED_ON } ]),
      "Mark reviewed spam events"
    )
    classified = exec_update(
      sanitize([ MARK_CLASSIFIED_SQL, { since: SPAM_WAVE_STARTED_ON } ]),
      "Mark classified spam events"
    )
    say "Marked #{reviewed} reviewed and #{classified} classified events as spam"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "spam_at values set here are indistinguishable from earlier marks"
  end

  private

  def sanitize(statement)
    ActiveRecord::Base.sanitize_sql(statement)
  end
end
