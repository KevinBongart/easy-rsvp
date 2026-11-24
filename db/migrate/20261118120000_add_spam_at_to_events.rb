# Adds a spam marker and flags the SEO spam wave that began on 2026-11-16.
#
# The classifier below was measured against a production snapshot taken on
# 2026-11-18: it flagged 5,730 of the 5,798 events created from 2026-11-16 on,
# and, when run without the date guard, no legitimate event created before
# then. The date guard and the RSVP ceilings are what keep it precise; do not
# remove them. The rules are frozen here on purpose so later changes to
# application code cannot change what this migration did.
class AddSpamAtToEvents < ActiveRecord::Migration[8.1]
  SPAM_WAVE_STARTED_ON = "2026-11-16"

  MARK_SPAM_SQL = <<~'SQL'
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
          OR title ~ '\d{3}\D{0,8}\d{3}\D{0,8}\d{4}'
          OR title ~ '[〖〗【】『』⦃⦄꧁꧂⟦⟧〘〙〔〕]'
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
    add_column :events, :spam_at, :datetime

    marked = exec_update(
      ActiveRecord::Base.sanitize_sql([ MARK_SPAM_SQL, { since: SPAM_WAVE_STARTED_ON } ]),
      "Mark spam events"
    )
    say "Marked #{marked} events created since #{SPAM_WAVE_STARTED_ON} as spam"
  end

  def down
    remove_column :events, :spam_at
  end
end
