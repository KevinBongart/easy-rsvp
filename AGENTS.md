# Easy RSVP — Agent Reference

Read [the Rails engineering playbook](https://github.com/KevinBongart/rails-engineering-playbook) for
the shared guidelines covering architecture, Ruby/Rails conventions, testing,
frontend design, security, dependencies, CI, operations, documentation, and agent
workflows. Clone it as a sibling of this repository and pull before relying on
it:

```sh
git clone git@github.com:KevinBongart/rails-engineering-playbook.git ../rails-engineering-playbook
git -C ../rails-engineering-playbook pull --ff-only
```

This file records Easy RSVP's current implementation and app-specific
exceptions. When work here produces a guideline that would apply to other
applications, add it to the playbook repository rather than to this file.

Use [the codebase assessment and remediation plan](docs/CODEBASE_ASSESSMENT.md) when
assessing this repository. The playbook describes the preferred direction;
it does not mean that its preferred stack or checks are already installed here.

## Product and access model

Easy RSVP is an accountless app for creating events and collecting yes/maybe/no
responses. There are no users, households, or Devise accounts. Keep this product
model when applying the playbook's authentication and ownership guidance.

- Public event URLs use a hashid plus a title slug.
- Organizer URLs additionally carry `Event#admin_token`, generated as a UUID.
  Organizer actions must match both the event and its token.
- Public RSVP deletion uses event-scoped session hashids. Organizer RSVP
  mutations find the response through the token-authorized event's association.
- The cross-event `/admin/events` dashboard uses HTTP Basic authentication from
  `ADMIN_USER` and `ADMIN_PASSWORD`, applied directly by
  `Admin::EventsController`. The separately named `Organizer*Controller` classes
  authorize event-scoped creator actions with `Event#admin_token`. An organizer
  token never grants access to the site-wide `Admin` namespace.
- Owner-approved policy: unpublished events block guest RSVP additions and
  deletions, including deletion by a guest who previously owned a response.
  Organizer editing and RSVP management remain available. Public mutations enforce
  publication before looking up or changing a response.

Never import Bon App's accepted security risks as Easy RSVP owner decisions.
Do not expose organizer links, tokens, credentials, or imported personal data in
documentation, logs, screenshots, or test fixtures.

## Current stack

Verified against the repository on 2026-09-18; the version files remain authoritative.

| Concern | Current implementation |
| --- | --- |
| Runtime | Ruby as pinned in `.ruby-version`; Rails as resolved in `Gemfile.lock` |
| Framework defaults | `config.load_defaults 8.1`, with a SHA-1 key-generator compatibility hold |
| Database | PostgreSQL; `events_development`, `events_test`, `events_production` |
| UI | ERB, Simple Form, Bootstrap 5.3.8 |
| Assets | Propshaft, dartsass-rails, jsbundling-rails/esbuild, Turbo, Stimulus, Action Text/Trix 2.1.19; browser packages locked with npm |
| Storage | Active Storage; disk in development/test, S3 in production |
| Mail | No application email feature; Action Mailer is not loaded |
| Tests | RSpec, FactoryBot, WebMock; Rack Test by default, Selenium/headless Firefox for `js: true` system specs |
| CI/deploy | CircleCI; Dokku app `easy-rsvp`, server configured through `DOKKU_HOST` |

The modern Rails asset pipeline and Bootstrap 5 are installed. The JavaScript
bundle imports only Bootstrap's Alert and Modal plugins; the application has no
jQuery dependency. Easy RSVP's `bin/ci` runs its own eager-loading,
asset-compilation, and RSpec checks.

## Code map and domain rules

- `Event`: title/date/publication validation, Action Text `body`, public hashid/slug,
  organizer token, non-null publication and RSVP-name visibility flags, dependent
  destruction of RSVPs. Events may remain date-only or add a complete same-day
  schedule: start time, required later end time, and IANA time zone. Blank start
  and end fields remove the schedule; entering either one requires both. Bare
  hours such as `7` mean `7:00 PM`. Timed values
  are stored as UTC timestamps and rendered in their event time zone. Published
  events expose an iCalendar download; date-only entries are all-day events and
  timed entries use exact UTC instants so calendar clients can display them in
  the viewer's chosen time zone. The legacy `events.body` values were
  backfilled into Action Text before that column was removed in a later deployment.
  Missing Action Text rows are repaired during removal; divergent legacy values
  are retained in `legacy_event_body_conflicts` for explicit review.
- `Rsvp`: belongs to an event, name/response presence validation,
  `RESPONSES = [:yes, :maybe, :no]`, with non-null database columns, a nonblank
  name check, and a supported-response check validated against existing rows.
- `ImageUpload`: legacy records retain old editor uploads and their Active
  Storage attachments. New editor uploads use Action Text direct uploads. The
  browser and server accept declared PNG/JPEG/GIF/WebP files from 1 byte through
  5 MB before issuing a storage URL. Direct uploads cannot be byte-sniffed
  before reaching storage. Upload ownership remains independent of event
  creation and needs a separate lifecycle design.
- Event limits: titles of at most 200 characters (`maxlength` on the inputs),
  descriptions of at most 20,000 characters of visible text
  (`Event::SpamCheck.visible_text`: markup and image payloads do not count,
  captions and pasted content attachments do), and at most 10 MB of embedded
  images per description. Images count once each: Action Text embeds by blob
  size, and images referenced only by an Active Storage URL (the former Trix
  uploader) by the size of the blob that URL's signed id resolves to; the
  submitted `filesize` is never trusted. The editor also counts images accepted
  earlier in the same multi-file drop or pick. Each limit is checked only when its field
  changes and only rejects a change that makes the value larger than before,
  so older events over a limit stay editable. Errors show under the title and
  the editor (`events/_body_error`). Direct uploads happen before the event
  exists, so the 10 MB total is also checked in the editor
  (`rich_text_controller.js`) before an upload starts; the server validation is
  authoritative.
- `EventsController`: event creation and public display.
- Spam and search indexing: event pages (public, calendar, organizer) send
  `X-Robots-Tag: noindex, nofollow` and a matching robots meta tag; the home page
  stays indexable. `UserContentLinkScrubber` keeps Action Text's default safe list
  and adds `rel="nofollow ugc noopener noreferrer"` to every rendered link; Action
  Text ignores its tag/attribute lists when a scrubber is set, so the scrubber
  carries them itself. `Event#spam_at` marks spam (`Event.spam` / `Event.not_spam` scopes) and
  `Event#spam_source` records who marked it. `Event::SpamCheck` runs on every
  save that changes the title or body and marks matches as `automatic`; it has
  named title and body rules tuned on the 2026-11 production snapshot (see the
  class comment). Its `non_editor_html` rule assumes the Trix editor. Public and
  RSVP routes answer `410 Gone` to guests for all spam. Organizers of
  `automatic` spam keep access and clear the mark by editing the event into
  something that passes. The code is public, so confident spammers are not
  told they were caught. `Event#confidently_spam?` (automatic, and 2+
  `SpamCheck` reasons or a Jev score of at least 0.98, computed on demand;
  `spam_verdict_hidden` keeps it true through later edits) makes the organizer
  pages look normal and serves the public page, calendar, and RSVPs normally
  to the browser that created or managed the event (`ManagedEvents`: the 20
  most recent hashids in the session, skipped during admin previews). Less
  certain flags show a neutral notice (`organizer_events/_spam_notice`) and
  stay `410` for everyone. Known limits: any other browser or script still
  gets `410`, and `RecentEventCreation` refusing the next creation reveals a
  spam verdict. `operator` marks (the `AddSpamAtToEvents` and
  `MarkMoreSpamEvents` migrations) are final and lock the organizer out with
  `410 Gone`. The `FlagUncheckedSpamEvents` migration ran the check once over
  events created before it existed. Body rules ignore only image payloads; text in figures,
  captions, and content attachments counts because Action Text renders it. The admin
  dashboard lists spam only under its Spam filter (`spam=1`) with creation
  times, badges automatic marks, and never counts spam in the stats. Each row
  has confirmed Mark spam / Not spam buttons; admin marks are `operator` marks
  set with `update_columns`, bypassing the save-time check. Not spam sets
  `spam_source = "cleared"` (with no `spam_at`) so automatic checks skip the
  event afterwards.
- Spam images (`Event::SpamImages`): Active Storage's blob and representation
  redirect/proxy controllers get `HidesOperatorSpamImages` prepended
  (`config/initializers/spam_images.rb`), which narrows `blob_scope` so the
  signed-id lookup itself excludes blobs embedded only in descriptions of
  `operator`-marked events: those answer 404, in the same single indexed query.
  Images of `automatic` and cleared events, blobs also attached elsewhere,
  unattached direct uploads, legacy `ImageUpload` blobs, and admin preview
  sessions are still served. Files on S3 are reached through 5-minute signed
  URLs, so a mark takes effect within minutes. `bin/rails spam:purge_images`
  (daily Dokku cron in `app.json`) deletes the embeds of operator marks older
  than 30 days (`spam_decided_at`, falling back to `spam_at`). Each attachment
  row and its blob row go in one transaction, so an interrupted run leaves the
  image hidden and the next run finds it; the stored file is deleted after the
  commit, and a failed storage delete is logged with its key, counted, and makes
  the task exit non-zero. It detaches blobs still attached to another record
  without purging them, is idempotent, and prints counts and bytes only. "Not spam"
  before then keeps the images. Legacy `ImageUpload` images predate the spam
  wave (that uploader was removed in September 2026) and are never hidden or
  purged.
- `Event::SpamReview` / `EventSpamReviewJob`: a second opinion from TypeSafe's
  Jev model (`TYPESAFE_API_KEY`; off when unset) for events the Ruby rules pass
  and no admin has decided on. The job is queued after commit on the in-process
  async adapter (two threads inside each Puma process; no worker process, so a
  restart can drop it), stores Jev's advertising score in
  `Event#spam_score`, and flags the event `automatic` at `THRESHOLD` (0.9); the
  organizer clears it the same way, by editing, which queues a new review.
  Errors fail open, so `SpamReviewStatus` (one row, `id = 1`) records Jev's
  health across restarts:
  - Columns: `last_succeeded_at`, the current streak's `failing_since` and
    `consecutive_failures`, and the latest `last_failed_at` and `last_error`.
  - `last_error` is the exception class, plus the message only for
    `Event::SpamReview::Error`, which states the HTTP status. For 401, 402, 403
    and 429 it adds the standard meaning; TypeSafe documents no codes, so 402
    reads "probably out of credits". It never holds event text or the key.
  - A success is one `upsert`; a failure updates the row under a lock. Only the
    API call counts: an error writing the status is reported on its own and
    never discards a score.
  - Honeybadger (`Rails.error`) hears only about the failure that starts a
    streak, so an outage sends one notice.
  - The admin dashboard shows a red alert above the stats while Jev is failing:
    since when, the streak, the last success and error, and how many events
    have no score, flag, or admin decision (`Event.without_spam_review`) since
    the earlier of the last success and five minutes before the first failure.
    That costs one query, plus the count while failing.
  - It also shows a red alert when `config.x.spam_review_required` (production
    only) is set without `TYPESAFE_API_KEY`.

  Under a row lock, the job writes only if the masked text it sent is still the
  event's text and no admin decided meanwhile. Jev cannot be
  fine-tuned, so admin decisions teach it in context: each request lists the 10
  most recent published "Not spam" events and the 10 most recent admin spam marks,
  ordered by `spam_decided_at`, which only the admin actions set. Editing a
  cleared event's text resets it, so organizers cannot inject text into other
  reviews. "Not spam" clicks from before the column existed have no decision
  time and are never examples. Masking truncates first and uses bounded
  regexes, because it runs on untrusted text under `Regexp.timeout`. Text is masked before it leaves the app (links reduced to domains,
  emails, phones, street addresses, UK postcodes); link targets hidden behind
  anchor text are appended as domains. Evaluated on the 2026-11 snapshot: 0.9
  flagged 5 of 11,368 legitimate events and caught 29 of 40 adversarial spam
  pages the Ruby rules missed; balanced examples removed those false positives
  without losing recall.
- `AdminPreview`: loading the Basic-Auth dashboard opens an admin session, an
  expiring flag (one day) in the encrypted Rails session cookie; no tokens appear
  in URLs. In that browser, event and organizer pages show an admin banner and
  render even when spam or unpublished, but the session never unlocks organizer
  edits, publication, or deletion. The banner offers the same Mark spam / Not
  spam buttons, posting to the Basic-Auth admin routes with a same-site
  `return_to`. "Close admin session" in the dashboard footer ends it.
- `RecentEventCreation`: at most 5 successful event creations per client per
  30 minutes, and none for 2 hours (`SPAM_BLOCK`) after creating an event
  that becomes spam, whatever decided it. The counter row records it
  (`spam_at`): at creation when the Ruby rules flag the event, by `Event`
  after save when an edit makes it spam (`became_spam?`), and by
  `RecentEventCreation.record_spam!` from the writes that skip callbacks
  (`EventSpamReviewJob`, admin Mark spam). It sticks: deleting the event or
  editing the spam away does not lift the block, because the code is public
  and either would otherwise cost a spammer one request. Only admin "Not spam"
  (`clear_spam!`) or the 2-hour expiry lifts it. A wrongly flagged organizer
  can still edit their event to clear its flag, but can't create another event
  from that IP (or IPv6 /64) for up to 2 hours. Clients are keyed by an HMAC of
  the remote IP (IPv6 reduced to its /64), never the raw address and never
  stored on the event; each row links to the event it created (foreign key
  nullified when the event is deleted) and is deleted, with the link, on the
  first creation attempt after it is 2 hours old. One query on the per-client
  index checks both rules inside a per-client Postgres advisory lock that
  serializes parallel submissions. Failed validations and refused attempts do
  not count. Both rules show the same `CREATION_LIMITED_MESSAGE` (429), which
  deliberately does not say which applied.
- `OrganizerEventsController`: organizer display, editing, deletion, publication.
- `RsvpsController`: public response creation and session-owned deletion.
- `OrganizerRsvpsController`: organizer response editing/deletion.
- `Admin::EventsController` / `Admin::EventStats`: dashboard listing and stats.
  Owner-approved rule: yearly/monthly counts and projections measure event creation
  using `created_at`, independent of scheduled `date`. Monthly numeric counts are
  computed once per presenter and formatted for display. The dashboard uses
  server-rendered 160 × 20 SVG sparklines with CSS hover/focus tooltips (no chart
  JavaScript). The yearly chart includes a separate actual point through today
  before its dashed December 31 projection. The monthly history ends with a dashed
  current-period projection;
  the current-month chart shows cumulative daily counts followed by a dashed
  forecast. Projections use the average per elapsed calendar day, including today,
  and account for month/year length. Missing periods are zero-filled. Monthly
  history includes 12 completed months plus the current projection. The all-time
  total includes the oldest creation date; current-year and current-month counts
  and projections are visible beside their charts. These statistics exclude spam;
  a last row reuses a second `Admin::EventStats` over `Event.spam` for the same
  monthly history and month-end projection of spam events (one grouped query),
  drawn as a red (`admin-sparkline-danger`, Bootstrap `$danger`) sparkline. Jev's
  score has its own monospaced column after the organizer link. The event list reports and can
  filter on persisted Action Text embeds using a correlated SQL query rather than
  loading attachments per event, and can filter to events with a specific time.
Use `db/schema.rb` and `config/routes.rb` for exact constraints and paths.
Keep controllers focused on HTTP; share repeated event-ID parsing and access
rules only after their different authorization boundaries are covered by tests.

## Validation and operations

Run `bin/ci` for all local CI checks or `bundle exec rspec` for the full suite.
Specs refuse any database but a local `events_test` or `events_test_<suffix>`;
parallel checkouts each set their own with
`DATABASE_URL=postgresql:///events_test_<suffix>`.
The full suite includes headless Firefox. Use `bundle exec rspec --tag ~js` for
fast checks and `bundle exec rspec spec/system/javascript_smoke_spec.rb` for
passing Firefox smoke flows. The database pull specs run without
booting Rails: `bundle exec rspec spec/lib/production_database_pull_spec.rb`.
For autoloading changes, run `RAILS_ENV=test bin/rails zeitwerk:check`.
CircleCI installs Firefox/geckodriver, creates and loads the test database, then
runs `bin/ci`. JUnit results and failure screenshots are retained. Bundler-audit,
Brakeman, Rails Omakase, ERB Lint, ESLint, and Stylelint run before the application
checks. The frontend linters use their upstream recommended rules without a
project-specific house style or generated suppression file. `npm audit` covers
shipped dependencies only (`--omit=dev`): development-only lint tooling never
reaches production and must not block deploys on advisories without a fix.

Before merging a substantive pull request, have a context-isolated agent
independently review the final diff against `origin/main` and these repository
instructions. Give the reviewer the acceptance criteria and final diff without
the implementing agent's reasoning, then resolve or explicitly disposition
material findings. Trivial automated dependency bumps limited to manifest and
lockfile version changes may rely on normal dependency review and passing CI;
require independent review when a bump includes conflicts, application or
configuration changes, migrations, security-sensitive behavior, or unexplained
failures.

Preserve review iterations in open pull requests. Make every material response
to review feedback a new commit so its incremental diff remains visible. Do not
amend, squash, force-push, or rebase away earlier PR commits unless the owner
explicitly requests rewritten history. Prefer merging the updated target branch
when synchronization is necessary; the repository's final merge policy may still
squash the completed PR.

Use factories, transactional data, and block-scoped time travel. The harness
supplies synthetic dashboard credentials and blocks external Ruby HTTP with
WebMock, allowing localhost for WebDriver. Active Storage uses a dedicated
temporary disk directory, and jobs use the test adapter.
System specs default to Rack Test; add `js: true` only for browser behavior.
Firefox specs enable real CSRF protection and restore the setting afterward.
Propshaft resolves development assets from current source. The development asset
regression boots that environment separately and checks stylesheet delivery
without accessing application data.
Trix smoke specs use the real editor and native file-drop events, with real local
upload/download requests. They also cover Turbo validation responses and modal
snapshot cleanup. Never replace them with a stubbed successful upload.

All 19 original pending regressions are fixed; the suite has no pending examples.
Do not add pending markers for new failures without reproducing and documenting
the defect. Regression expectations must continue to execute after fixes. No application services exist under `app/services` today; the
production-database utility and command runner are unit-tested under `spec/lib`.

`bin/dev` runs the Rails server plus Dart Sass and JavaScript watchers through
Foreman. SCSS changes compile automatically and Propshaft serves their new
fingerprint on refresh; normal development never needs manual asset clean,
clobber, or build tasks. Development uses a process-specific manifest path so
precompiled output left by local CI cannot override current source. Development uploads and imported
`amazon` blobs resolve to local disk under
`storage/development`. Imported images require a separately authorized local
file copy; no remote fallback exists. Ordinary tests use local storage. Do not exercise external side effects without the
user's authorization.

`db:pull_production` exports production over SSH and replaces only local
`events_development` after confirmation and a validated backup. Its usage and
recovery files are documented in the [README](README.md). Adding or testing its
code is separate from running an actual production import.
`db:backup_production` uses the same guarded export path to create a timestamped
archive under ignored `db/backups/` without changing either database. It checks
the archive catalog and reads the complete archive, but only a disposable restore
drill proves usability; require that drill before destructive use.

Production and staging database access has a stricter boundary. An agent may
pull either database only by invoking a dedicated, repository-owned, guarded
Rake task, and only when the user explicitly authorizes that specific pull.
`db:pull_production` and `db:backup_production` are the only approved production
database interfaces. A staging pull is prohibited unless an equivalent guarded
task exists in the repository. Never
reproduce or bypass a pull task's internals: do not invoke `ssh`, `scp`, `pg_dump`,
`psql`, Dokku commands, or a remote database connection directly, even for
read-only inspection. If the task cannot provide required information, ask the
user to provide it.

Never commit, push, or deploy automatically. CircleCI deploys successful `main`
builds, so a push to `main` has a production side effect.
Deploy jobs share a CircleCI `serial-group`, so they run one at a time; when a
newer `main` pipeline is waiting or deploying, older queued deploys are skipped
("not run"). The deploy skips documentation-only changes by diffing against the
revision Dokku reports (`git:report --git-sha`) and deploys if that is unknown.

Trix and the matching Action Text JavaScript are locked npm dependencies and
loaded through the jsbundling-rails entry point, following the Rails generator's
Node-bundling path; do not add a separate application Trix build. Propshaft
handles digests and Subresource Integrity, esbuild compiles JavaScript, and
dartsass-rails compiles Bootstrap and application SCSS.
The Node buildpack runs before the Ruby buildpack in `.buildpacks`; keep that
order. `bin/ci` installs and audits the locked npm graph, then uses Rails'
`assets:precompile` hooks to build browser dependencies and fingerprint CSS.
Node 24 is selected by
`.node-version` locally and `package.json` during buildpack deploys.

Application log formatters and Honeybadger notice callbacks redact organizer URL
segments and UUID-shaped credentials. Honeybadger session reporting and Insights
are disabled. Dokku's `app.json` postdeploy task reports its injected `GIT_REV`
and fails visibly on missing configuration or notification errors. See
`docs/ORGANIZER_LOG_PRIVACY.md` for proxy rollout; application redaction alone
does not establish production proxy/log-collector privacy.
