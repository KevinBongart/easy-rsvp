# Unrelated production tables

The production database snapshot imported on September 15, 2026 contains 19
tables that are not part of Easy RSVP. They appear to belong to several older
applications:

- `action_text_rich_texts`, `admins`, `categories`, `entries`, `gifts`,
  `imports`, `line_items`, `lists`, and `payments`
- `card_games`, `card_players`, `cards`, `games`, `options`, `packs`, `players`,
  `rounds`, and `submissions`
- `records`

Together they occupy approximately 1.1 GB. The largest tables contain about
5.6 million `card_games` rows, 1.96 million `submissions` rows, and 1.45 million
`card_players` rows. The existing Action Text table contains 107 rows owned by
`Entry`, `Gift`, and `List`; none belong to `Event`.

Easy RSVP's `events`, `rsvps`, and `image_uploads` tables remain in place. Its
Active Storage tables also remain because every current attachment belongs to
an `ImageUpload`.

## Deployment

Before merging the quarantine migration:

1. Confirm that every other application has been disconnected from Easy RSVP's
   PostgreSQL service and given its own database. Renaming these tables will
   break an application that is still using them.
2. Take and validate a fresh production database backup.
3. Deploy during a quiet period. PostgreSQL table renames are metadata changes,
   but they require an exclusive lock on each table.
4. Verify Easy RSVP event display, organizer editing, RSVP submission, and image
   upload behavior after deployment.

The migration prefixes each unrelated table with `quarantined_20260915_` and
preserves its rows, indexes, sequences, and foreign keys. It also renames the
Action Text uniqueness index so a later Action Text installation can create the
canonical table and index names.

Run `bin/rails db:rollback` to restore the original names before installing
Action Text again. Dropping the quarantined tables should be a later, explicit
migration after a retention period and confirmation that no other application
needs the data.
