# Easy RSVP

An accountless app to organize events and invite people.

Read more: https://www.kevinbongart.net/projects/easy-rsvp.html

## Development

Use Ruby from `.ruby-version` and a running local PostgreSQL server:

```sh
bundle install
cp .env.sample .env # only on first setup; preserve an existing .env
bin/rails db:prepare
bin/dev
```

Configure the environment values needed by the flows you use. The dashboard
uses `ADMIN_USER` and `ADMIN_PASSWORD`. Organizer-link emails use the `SMTP_*`
settings and `DOMAIN`. Development uploads use `storage/development`, and organizer-link emails are
written under `tmp/mail` for local inspection. No SMTP or S3 credentials are
needed for those development flows.

## Tests

Install Firefox and geckodriver alongside the bundled test gems. On macOS,
Firefox may be installed as `/Applications/Firefox.app`; `FIREFOX_BINARY` can
select another installation. geckodriver must be on `PATH` (for example through
Homebrew). CircleCI installs both with its browser-tools orb.

Prepare the local test database on first setup:

```sh
RAILS_ENV=test bin/rails db:create db:schema:load
```

Run the same checks as CircleCI (Bundler-audit, Brakeman, Rails eager loading, asset compilation, and the
entire randomized RSpec suite, including headless Firefox):

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
presenter units, mailers, HTTP requests, independent
organizer/guest sessions, database-import services, Rack Test form flows, and
real browser interactions. Firefox actually drops a PNG into Trix, submits it
through the upload endpoint, waits for the returned image to load, saves it with
an event, reloads the public page, and edits text while preserving the image.
Clipboard, RSVP-again, Bootstrap modals, and Rails UJS deletion also have smoke
coverage. Firefox specs enable real CSRF protection, including for uploads.
Browser specs resolve current asset source even if compiled files exist.
Development also resolves current asset source so local CI precompilation cannot
leave it serving stale styles or scripts. Restart an already running development
server after changing environment configuration (`bin/rails restart` for Puma).
Admin chart coverage checks real Firefox hover/focus tooltips, navigation, empty
data, and narrow layouts, alongside unit tests for projections and chart scaling.

Tests require local `events_test`. They use synthetic dashboard credentials,
transactional records, a temporary disk storage directory removed after the
suite, test email/jobs, and WebMock to reject external Ruby HTTP requests.
WebDriver's localhost traffic is allowed. No production imports or real S3/SMTP
operations are part of the suite.

All 19 original pending expectations now pass. Guest RSVP additions/deletions are
blocked on unpublished events while organizer editing remains available. Dashboard
counts and projections use creation dates. Public image uploads require detected
PNG/JPEG/GIF/WebP content and a maximum size of 10 MB; failed Trix uploads show an
error and permit another attempt. Production email links require `DOMAIN` (a host
without a URL scheme) and use HTTPS.

The RSVP migration enforces supported response values on new writes using a
PostgreSQL `NOT VALID` check constraint. It leaves historical records unchanged;
review any invalid values before validating the existing rows in a later migration.
The migration has been applied and reversed only against the local test database.

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
successful `main` builds to Dokku. Bundler-audit and Brakeman are security gates in `bin/ci`; linting remains an assessment follow-up.

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
| `PG_BIN` | Directory containing all four PostgreSQL tools, if automatic discovery selects the wrong version or finds none |
| `CONFIRM_PULL_PRODUCTION` | Set to exactly `events_development` for an intentional noninteractive replacement |

Also set `DOKKU_HOST` in CircleCI project environment variables before deploying.
The deploy job uses its hostname portion and connects as the `dokku` user; the
import task uses the full SSH destination.

The production database is only exported. The remote temporary dump is removed
after copying; a cleanup failure is reported. Production and pre-import local
archives remain under ignored `tmp/database_backups/`, with directory mode `0700`
and archive mode `0600`. Keep the previous local archive until the import is
verified, then delete unneeded copies containing real user data.

After importing, apply any pending local migrations with `bin/rails db:migrate`.
This task copies database rows only; it does not copy attachment files. In
development, imported `amazon` blobs resolve to local disk, and email stays in
`tmp/mail`. Imported images are unavailable until their files are copied into
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

## Updating the editor

Trix 2.1.19 and DOMPurify 3.4.15 are pinned through `package-lock.json`. Node
24.13.0 is selected locally by `.node-version`; buildpack deploys follow the
`24.x` range in `package.json` so security patch releases remain available.

Run `npm ci --ignore-scripts` after checking out or updating the lockfile.
`bin/dev` builds Trix before starting Rails. `bin/ci` installs and audits the npm
graph, rebuilds Trix with the pinned DOMPurify release, compiles the resulting
files through Sprockets, and exercises the real Firefox paste/upload specs. The
generated Trix JS/CSS files are ignored and are not committed.

Dokku uses the pinned Node and Ruby buildpacks in `.buildpacks`, in that order.
The Node buildpack runs `npm ci` and `npm run build`; the Ruby buildpack then
compiles the generated files with the rest of the Rails assets. `BUILDPACK_URL`
must not be set for the app because it overrides the ordered buildpack list.
