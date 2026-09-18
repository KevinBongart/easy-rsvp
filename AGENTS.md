# Easy RSVP — Agent Reference

Read [the Rails engineering playbook](docs/RAILS_ENGINEERING_PLAYBOOK.md) for
the shared guidelines covering architecture, Ruby/Rails conventions, testing,
frontend design, security, dependencies, CI, operations, documentation, and agent
workflows. It was copied from `../bon_app` at the owner's request. This file
records Easy RSVP's current implementation and app-specific exceptions.

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
  `ADMIN_USER` and `ADMIN_PASSWORD`. `Admin::AdminController` is the dashboard
  base; `Admin::BaseController` handles organizer tokens. They are different
  access boundaries despite their similar names.
- Owner-approved policy: unpublished events block guest RSVP additions and
  deletions, including deletion by a guest who previously owned a response.
  Organizer editing and RSVP management remain available. Public mutations enforce
  publication before looking up or changing a response.

Never import Bon App's accepted security risks as Easy RSVP owner decisions.
Do not expose organizer links, tokens, credentials, or imported personal data in
documentation, logs, screenshots, or test fixtures.

## Current stack

Verified against the repository on 2026-09-15; the version files remain authoritative.

| Concern | Current implementation |
| --- | --- |
| Runtime | Ruby 3.3.4; Rails 8.1.3.1 in `Gemfile.lock` |
| Framework defaults | `config.load_defaults 5.2`, with later defaults initializers |
| Database | PostgreSQL; `events_development`, `events_test`, `events_production` |
| UI | ERB, Simple Form, Bootstrap 5.3.8 |
| Assets | Propshaft, dartsass-rails, jsbundling-rails/esbuild, Turbo, Stimulus, Action Text/Trix 2.1.19; browser packages locked with npm |
| Storage | Active Storage; disk in development/test, S3 in production |
| Mail | Action Mailer; file delivery in development, test delivery in test, SMTP in production; organizer-link delivery is synchronous |
| Tests | RSpec, FactoryBot, WebMock; Rack Test by default, Selenium/headless Firefox for `js: true` system specs |
| CI/deploy | CircleCI; Dokku app `easy-rsvp`, server configured through `DOKKU_HOST` |

The modern Rails asset pipeline and Bootstrap 5 are installed. The JavaScript
bundle imports only Bootstrap's Alert and Modal plugins; the application has no
jQuery dependency. Easy RSVP's `bin/ci` runs its own eager-loading,
asset-compilation, and RSpec checks.

## Code map and domain rules

- `Event`: title/date validation, Action Text `body`, public hashid/slug,
  organizer token, publication and RSVP-name visibility flags, dependent
  destruction of RSVPs. The legacy `events.body` values were backfilled into
  Action Text before that column was removed in a later deployment.
- `Rsvp`: belongs to an event, name/response presence validation,
  `RESPONSES = [:yes, :maybe, :no]`, with inclusion validation and a database check
  that is validated against existing rows as well as enforced for new writes.
- `ImageUpload`: legacy records retain old editor uploads and their Active
  Storage attachments. New editor uploads use Action Text direct uploads. The
  browser and server accept declared PNG/JPEG/GIF/WebP files from 1 byte through
  10 MB before issuing a storage URL. Direct uploads cannot be byte-sniffed
  before reaching storage. Upload ownership remains independent of event
  creation and needs a separate lifecycle design.
- `EventsController`: event creation and public display.
- `EventsAdminController`: organizer display, editing, deletion, publication.
- `RsvpsController`: public response creation and session-owned deletion.
- `Admin::RsvpsController`: organizer response editing/deletion.
- `Admin::EmailRequestsController` / `UserMailer`: email the organizer link.
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
  and projections are visible beside their charts.
Use `db/schema.rb` and `config/routes.rb` for exact constraints and paths.
Keep controllers focused on HTTP; share repeated event-ID parsing and access
rules only after their different authorization boundaries are covered by tests.

## Validation and operations

Run `bin/ci` for all local CI checks or `bundle exec rspec` for the full suite.
The full suite includes headless Firefox. Use `bundle exec rspec --tag ~js` for
fast checks and `bundle exec rspec spec/system/javascript_smoke_spec.rb` for
passing Firefox smoke flows. The database pull specs run without
booting Rails: `bundle exec rspec spec/lib/production_database_pull_spec.rb`.
For autoloading changes, run `RAILS_ENV=test bin/rails zeitwerk:check`.
CircleCI installs Firefox/geckodriver, creates and loads the test database, then
runs `bin/ci`. JUnit results and failure screenshots are retained. Bundler-audit and Brakeman run before the application checks; lint remains a follow-up.

Use factories, transactional data, and block-scoped time travel. The harness
supplies synthetic dashboard credentials and blocks external Ruby HTTP with
WebMock, allowing localhost for WebDriver. Active Storage uses a dedicated
temporary disk directory, mail uses test delivery, and jobs use the test adapter.
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
`storage/development`; organizer-link emails are written to `tmp/mail`. Imported
images require a separately authorized local file copy; no remote fallback exists.
Ordinary tests use local storage and test delivery. Do not exercise external side effects without the
user's authorization.

`db:pull_production` exports production over SSH and replaces only local
`events_development` after confirmation and a validated backup. Its usage and
recovery files are documented in the [README](README.md). Adding or testing its
code is separate from running an actual production import.

Production and staging database access has a stricter boundary. An agent may
pull either database only by invoking a dedicated, repository-owned, guarded
Rake task, and only when the user explicitly authorizes that specific pull.
`db:pull_production` is the only approved production interface. A staging pull
is prohibited unless an equivalent guarded task exists in the repository. Never
reproduce or bypass a pull task's internals: do not invoke `ssh`, `scp`, `pg_dump`,
`psql`, Dokku commands, or a remote database connection directly, even for
read-only inspection. If the task cannot provide required information, ask the
user to provide it.

Never commit, push, or deploy automatically. CircleCI deploys successful `main`
builds, so a push to `main` has a production side effect.

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
