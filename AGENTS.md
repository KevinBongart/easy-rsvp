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

Verified against the repository on 2026-09-08; the version files remain authoritative.

| Concern | Current implementation |
| --- | --- |
| Runtime | Ruby 3.3.4; Rails 8.1.3.1 in `Gemfile.lock` |
| Framework defaults | `config.load_defaults 5.2`, with later defaults initializers |
| Database | PostgreSQL; `events_development`, `events_test`, `events_production` |
| UI | ERB, Simple Form, Bootstrap 4.6.2.1 |
| Assets | Sprockets, SassC, CoffeeScript, jQuery, Rails UJS, Turbolinks, Trix 2.1.19 built with npm/esbuild |
| Storage | Active Storage; S3 in development/production, disk in test |
| Mail | Action Mailer with SMTP; organizer-link delivery is synchronous |
| Tests | RSpec, FactoryBot, WebMock; Rack Test by default, Selenium/headless Firefox for `js: true` system specs |
| CI/deploy | CircleCI; Dokku app `easy-rsvp`, server configured through `DOKKU_HOST` |

The legacy frontend is the current implementation, not a permanent exemption
from the playbook. Modernize incrementally behind browser coverage. Do not use
Bon App's importmap, Stimulus, Propshaft, or npm lint commands here:
those components do not currently exist. Easy RSVP's `bin/ci` runs its own
eager-loading, asset-compilation, and RSpec checks.

## Code map and domain rules

- `Event`: title/date validation, public hashid/slug, organizer token,
  publication and RSVP-name visibility flags, dependent destruction of RSVPs.
- `Rsvp`: belongs to an event, name/response presence validation,
  `RESPONSES = [:yes, :maybe, :no]`, with inclusion validation and a database check
  for new writes. Historical rows still need review before validating the constraint.
- `ImageUpload`: one required PNG/JPEG/GIF/WebP image, at most 10 MB. The upload
  endpoint detects MIME type from file bytes. Upload ownership remains independent
  of event creation and needs a separate lifecycle design.
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
- `ImageUploadsController`: JSON upload endpoint for the editor.

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
Development and test resolve assets from current source, bypassing precompiled
manifests left by local CI. The development asset regression boots that environment
separately and checks stylesheet delivery without accessing application data.
Trix smoke specs use the real editor and native file-drop events, with real local
upload/download requests. Never replace them with a stubbed successful upload.

All 19 original pending regressions are fixed; the suite has no pending examples.
Do not add pending markers for new failures without reproducing and documenting
the defect. Regression expectations must continue to execute after fixes. No application services exist under `app/services` today; the
production-database utility and command runner are unit-tested under `spec/lib`.

`bin/dev` runs the Rails server. Development uploads use the configured S3 bucket
and organizer-link requests can send real SMTP email. Ordinary tests use local
storage and test delivery. Do not exercise external side effects without the
user's authorization.

`db:pull_production` exports production over SSH and replaces only local
`events_development` after confirmation and a validated backup. Its usage and
recovery files are documented in the [README](README.md). Adding or testing its
code is separate from running an actual production import.

Never commit, push, or deploy automatically. CircleCI deploys successful `main`
builds, so a push to `main` has a production side effect.

Trix is pinned in `package-lock.json` and generated with `npm run build` before
Sprockets compiles assets. The Node buildpack runs before the Ruby buildpack in
`.buildpacks`; keep that order. `bin/ci` installs and audits the locked npm graph,
builds Trix with the pinned DOMPurify version, and then compiles assets. Node 24
is selected by `.node-version` locally and `package.json` during buildpack deploys.
