# Easy RSVP

An accountless app to organize events and invite people.

Read more: https://www.kevinbongart.net/projects/easy-rsvp.html

## Development

Use Ruby from `.ruby-version`, Node from `.node-version`, and a running local
PostgreSQL server:

```sh
test -e .env || cp .env.sample .env
bin/setup
```

`bin/setup` installs the Ruby and npm dependencies, prepares the database, and
starts `bin/dev`. Pass `--skip-server` when only preparing the checkout. No seed
data is required. Development uploads use `storage/development` and do not need
S3 credentials.

The event creation and RSVP flows need no environment configuration locally.
Set both `ADMIN_USER` and `ADMIN_PASSWORD` to use the site-wide dashboard at
`/admin/events`. The application does not send email.

Rails applies best-effort per-IP limits to event creation, event-scoped RSVP
changes, and direct-upload authorization. Failed dashboard authentication has a
separate per-IP limit; successful authentication clears prior failures. Exceeded
requests return `429 Too Many Requests` with `Retry-After`. Production uses the
application cache, so these limits reset on deploy and must move to a shared cache
or verified proxy controls if the web process is scaled across hosts.

## Product and access rules

Easy RSVP has no accounts. A published event has a public URL for guests and a
separate organizer URL containing a secret token. Anyone with the organizer URL
can edit or publish the event and manage all its RSVPs; that token does not grant
access to the site-wide dashboard.

Guests can delete only RSVPs created in their current browser session. When an
event is unpublished, its public page is unavailable and guests cannot add or
delete RSVPs, including ones their session previously created. Existing RSVPs
are preserved. The organizer can still edit the event and its RSVPs, and
republishing restores public access. Deleting an event through its
token-authorized endpoint also deletes its RSVPs, although the current interface
does not expose an event-deletion control.

The HTTP Basic-authenticated dashboard shows creation-date statistics; an
event's scheduled date does not affect those charts. Its event list shows
attachment count and stored size, can show only events with attachments, and can
sort by ID, RSVP count, or attachment size.

## Configuration

The checked-in `.env.sample` contains the settings commonly needed for local
development and operations. Keep secrets in an untracked `.env` locally and in
the deployment environment in production.

| Setting | When it is needed |
| --- | --- |
| `ADMIN_USER`, `ADMIN_PASSWORD` | Both are required to open the site-wide dashboard. |
| `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` | Production Active Storage access; development and tests use disk. |
| `HONEYBADGER_API_KEY` | Production exception reports and postdeploy markers. |
| `DOKKU_HOST` | CircleCI deploys and the guarded production database tasks. |
| `DOKKU_PG_SERVICE` | Production database backup/import tasks only. |
| `PG_BIN` | Optional PostgreSQL client directory when automatic discovery is unsuitable. |
| `FIREFOX_BINARY` | Optional nonstandard Firefox path for browser specs. |
| `SCOUT_APM_API_KEY` | Optional Scout APM reporting in production. |
| `RAILS_YJIT=false` | Optional production override to disable Rails' default YJIT. |

Dokku supplies database connection and revision values during deploys. The app
has no `DOMAIN` setting: absolute public and organizer links use the host and
scheme of the current HTTPS request. Configure the canonical hostname and TLS at
the Dokku/nginx boundary so organizer pages display the intended URLs.

## Tests

Install Firefox and geckodriver alongside the bundled test gems. On macOS,
Firefox may be installed as `/Applications/Firefox.app`; `FIREFOX_BINARY` can
select another installation. geckodriver must be on `PATH` (for example through
Homebrew). CircleCI installs both with its browser-tools orb.

Prepare the local test database on first setup:

```sh
RAILS_ENV=test bin/rails db:create db:schema:load
```

Run the same checks as CircleCI (Bundler-audit, Brakeman, Rails Omakase linting,
Rails eager loading, asset compilation, and the entire randomized RSpec suite,
including headless Firefox):

```sh
bin/ci
```

Useful focused commands:

```sh
bundle exec rspec --tag '~js'                 # fast model/request/feature/unit tests
bundle exec rspec spec/system/javascript_smoke_spec.rb  # passing Firefox smoke flows
bundle exec rspec --tag js                    # all Firefox smoke and failure-recovery specs
bundle exec rspec --seed 18467                # reproduce a full-suite ordering
```

The suite has no pending regressions and covers models,
presenter units, HTTP requests, independent
organizer/guest sessions, database import/backup utilities, Rack Test form flows, and
real browser interactions. Firefox actually drops a PNG into Trix, submits it
through Active Storage's direct-upload endpoint, waits for the returned image to load, saves it with
an event, reloads the public page, and edits text while preserving the image.
Clipboard, RSVP-again, Bootstrap modals, Turbo validation responses, modal cache
cleanup, and Turbo deletion also have smoke coverage. Firefox specs enable real
CSRF protection, including for uploads.
Propshaft resolves current source in development, so local CI precompilation cannot
leave it serving stale styles or scripts. Restart an already running development
server after changing environment configuration (`bin/rails restart` for Puma).
Admin chart coverage checks real Firefox hover/focus tooltips, navigation, empty
data, and narrow layouts, alongside unit tests for projections and chart scaling.

Tests require local `events_test`. They use synthetic dashboard credentials,
transactional records, a temporary disk storage directory removed after the
suite, test jobs, and WebMock to reject external Ruby HTTP requests.
WebDriver's localhost traffic is allowed. No production imports or real S3
operations are part of the suite.

All 19 original pending expectations now pass. Guest RSVP additions/deletions are
blocked on unpublished events while organizer editing remains available. Dashboard
counts and projections use creation dates. The editor and direct-upload endpoint
accept declared PNG/JPEG/GIF/WebP files between 1 byte and 10 MB; failed Trix
uploads show an error and permit another attempt. Because files upload directly
to storage, the endpoint can enforce declared metadata and signed upload length
but cannot inspect the bytes before issuing the storage URL. If organizer-link
email delivery is ever restored, it should be designed and verified as a new
feature rather than relying on the removed legacy implementation.

The RSVP migrations enforce supported response values with a validated PostgreSQL
check constraint. An aggregate review of the production-derived development data
found no invalid responses, so validation required no data cleanup or coercion.

The admin dashboard shows the all-time total with its earliest creation date,
current-year count and projection, and current-month count and projection alongside
three compact blue charts: annual counts, the last 12 completed months plus this month,
and this month's running daily total. Solid lines show actual counts; dashed
segments show extrapolations at the current average per calendar day (including
today). Hover, tap, or keyboard-focus a point for its count; the current endpoint
of the monthly history includes both the actual count so far and the estimated final total.
The yearly chart has separate points for this year's actual count through today
and its December 31 projection, connected by a dashed segment.
These are server-rendered SVGs with CSS tooltips and no charting dependency.

`bin/ci` writes JUnit results to `tmp/test-results/rspec.xml`. Failed system tests
save screenshots under `tmp/screenshots/`; CircleCI retains both. CircleCI deploys
successful `main` builds to Dokku. The app exposes Rails' lightweight `/up`
health endpoint, which Dokku must successfully probe before switching production
traffic to a new web container. After that switch, the `app.json` postdeploy task
reports Dokku's exact `GIT_REV` to Honeybadger. The task fails
visibly when its configuration or request fails, so a missing deploy marker
cannot be mistaken for success. Bundler-audit, Brakeman, and Rails Omakase are
gates in `bin/ci`. Pull requests that change
only Markdown files or files under `docs/` skip the expensive application checks.
A documentation-only commit on `main` also skips the production deploy.

## Back up the production database

Create a private, timestamped PostgreSQL archive and download it to the ignored
`db/backups/` directory:

```sh
bin/rails db:backup_production
```

The task requires `DOKKU_HOST` and `DOKKU_PG_SERVICE`, using the same settings
as the development database import below. It creates a temporary export on
Dokku, downloads it through a reserved local partial file, checks the
archive catalog and reads the complete archive with `pg_restore`, publishes it
with owner-only permissions, and removes the remote temporary file. Cleanup
failure makes the task fail and reports the exact remote path. It does not
change either the production or development database. Treat every downloaded
archive as production user data and keep it out of source control.

These checks catch truncation and archive read errors, but only a successful
restore proves that a backup is usable. Before an irreversible migration,
restore the new archive into a disposable local database and inspect the data.

## Refresh development data from Dokku

Stop local Rails servers/consoles holding database connections, and ensure
`events_development` exists (`bin/rails db:create` on first setup). You need SSH
and SCP access to the Dokku server, plus `pg_dump`, `pg_restore`, `dropdb`, and
`createdb` compatible with the production PostgreSQL version.

Set `DOKKU_HOST` to the SSH destination and `DOKKU_PG_SERVICE` to the linked
Dokku **PostgreSQL service** (which can differ from the app name). Both are
required and can be set in your untracked `.env`:

```sh
DOKKU_HOST=root@your-dokku-host DOKKU_PG_SERVICE=your-service-name bin/rails db:pull_production
```

The task prompts you to type `events_development`. It refuses other database
names, non-development Rails environments, and remote destination hosts. It
exports production to a temporary file on Dokku, copies and validates the dump,
backs up and validates the existing development database, then replaces it.
It resets Rails' database environment metadata to development and attempts to
restore the previous local database automatically if replacement fails.

| Setting | Purpose |
| --- | --- |
| `DOKKU_PG_SERVICE` | Required linked PostgreSQL service name; no guessed default |
| `DOKKU_HOST` | Required SSH destination, e.g. `root@your-dokku-host`; no default |
| `PG_BIN` | Directory containing PostgreSQL tools, if automatic discovery selects the wrong version or finds none |
| `CONFIRM_PULL_PRODUCTION` | Set to exactly `events_development` for an intentional noninteractive replacement |

Also set `DOKKU_HOST` in CircleCI project environment variables before deploying.
The deploy job uses its hostname portion and connects as the `dokku` user; the
import task uses the full SSH destination.

Configure `HONEYBADGER_API_KEY` in the Dokku app environment before merging a
deployment that includes monitoring. A key in the local `.env` configures only
local processes and is not copied to Dokku. Honeybadger error reporting is
disabled in development and test; production reports exceptions without session
data or Insights telemetry. Organizer-token URL segments and UUID-shaped values
are scrubbed from both application logs and Honeybadger notices.

Rails enables YJIT in production. If its memory overhead is unsuitable for the
Dokku host, set `RAILS_YJIT=false` on the app and restart it; the application
will boot without enabling YJIT. Removing the setting restores the Rails default.

The production database is only exported. The remote temporary dump is removed
after copying; a cleanup failure is reported. Production and pre-import local
archives remain under ignored `tmp/database_backups/`, with directory mode `0700`
and archive mode `0600`. Keep the previous local archive until the import is
verified, then delete unneeded copies containing real user data.

After importing, apply any pending local migrations with `bin/rails db:migrate`.
This task copies database rows only; it does not copy attachment files. In
development, imported `amazon` blobs resolve to local disk. Imported images are
unavailable until their files are copied into
local storage through a separately authorized export. Never fall back to S3
for missing local files. Unknown storage service names fail closed.

The import tests use fake commands and never access Dokku or replace a database:

```sh
bundle exec rspec spec/lib/production_database_pull_spec.rb
```

## Engineering and assessment

- [Rails engineering playbook](docs/RAILS_ENGINEERING_PLAYBOOK.md), copied from Bon App
- [Current application and agent reference](AGENTS.md)
- [Codebase assessment and remediation plan](docs/CODEBASE_ASSESSMENT.md)

## Assets and editor

The application uses the standard Rails 8 asset stack: Propshaft for digests and
delivery, dartsass-rails for Bootstrap and application SCSS,
jsbundling-rails/esbuild for JavaScript, Turbo for navigation, and Stimulus for
small interactions. The layout loads integrity-protected CSS and JavaScript with
`data-turbo-track="reload"`, so Turbo reloads the page when either compiled asset
changes.

Action Text owns event descriptions, Trix integration, rendering, and Active
Storage direct uploads. Trix 2.1.19 and the matching Rails Action Text JavaScript
are locked npm dependencies and imported by the application entry point, as the
Action Text generator does for Node-bundled Rails apps. There is no custom Trix
download or build script.
The original `events.body` values were migrated into Action Text before the
legacy column was removed in a later deployment. That removal backfills any
missing Action Text rows and preserves divergent cutover values in
`legacy_event_body_conflicts` for explicit review.
Rich-text images render from their original blobs, so production does not need
ImageMagick or libvips for this feature.
Bootstrap 5.3.8 is built from its locked npm package. The JavaScript bundle
imports only the Alert and Modal plugins used by the app and is minified for
delivery. Bootstrap's required Popper peer remains locked but is excluded from
the bundle because neither plugin uses it. jQuery and the old vendored
JavaScript copies are gone.

Run `npm ci` after checking out or updating the lockfile. Use `bin/dev` for local
development; it starts Rails plus the Dart Sass and JavaScript watchers. Saving
an SCSS file rebuilds the stylesheet automatically, and Propshaft serves its new
fingerprint on refresh. Normal development never requires `assets:clean`,
`assets:clobber`, or a manual Sass build. Development deliberately ignores any
precompiled manifest left in `public/assets`, so local CI output cannot pin the
server to stale files. `bin/ci` audits the locked npm graph,
builds both asset entrypoints through Rails' `assets:precompile` hooks, and
exercises the real Firefox paste/upload specs. Node 24.13.0 is selected locally
by `.node-version`; buildpack deploys follow the `24.x` range in `package.json`.

Dokku uses the pinned Node and Ruby buildpacks in `.buildpacks`, in that order.
The Node buildpack runs `npm ci` and `npm run build`; the Ruby buildpack then
reinstalls the locked JavaScript build dependencies, builds Sass through its
Ruby gem, and precompiles all assets with Propshaft. This remains valid after the
Node buildpack prunes development dependencies. Do not set
`SKIP_YARN_INSTALL` on Dokku: unlike CI, the Ruby stage needs those install hooks
to restore the pruned build tools. `BUILDPACK_URL` must not be set for the app
because it overrides the ordered buildpack list.

Organizer URL logging and proxy rollout are covered in
[Organizer link privacy](docs/ORGANIZER_LOG_PRIVACY.md).
