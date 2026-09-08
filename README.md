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
settings and `DOMAIN`. Development uploads currently use the S3 service in
`config/storage.yml`, so uploading or deleting attachments can affect real
storage; organizer-link requests can send real email.

## Tests

Install Firefox and geckodriver alongside the bundled test gems. On macOS,
Firefox may be installed as `/Applications/Firefox.app`; `FIREFOX_BINARY` can
select another installation. geckodriver must be on `PATH` (for example through
Homebrew). CircleCI installs both with its browser-tools orb.

Prepare the local test database on first setup:

```sh
RAILS_ENV=test bin/rails db:create db:schema:load
```

Run the same checks as CircleCI (Rails eager loading, asset compilation, and the
entire randomized RSpec suite, including headless Firefox):

```sh
bin/ci
```

Useful focused commands:

```sh
bundle exec rspec --tag '~js'                 # fast model/request/feature/unit tests
bundle exec rspec spec/system/javascript_smoke_spec.rb  # passing Firefox smoke flows
bundle exec rspec --tag js                    # all Firefox specs, including known regressions
bundle exec rspec --seed 18467                # reproduce a full-suite ordering
```

The suite has 144 examples (12 known pending regressions) and covers models,
presenter units, mailers, HTTP requests, independent
organizer/guest sessions, database-import services, Rack Test form flows, and
real browser interactions. Firefox actually drops a PNG into Trix, submits it
through the upload endpoint, waits for the returned image to load, saves it with
an event, reloads the public page, and edits text while preserving the image.
Clipboard, RSVP-again, Bootstrap modals, and Rails UJS deletion also have smoke
coverage. Firefox specs enable real CSRF protection, including for uploads.
Browser specs resolve current asset source even if compiled files exist.

Tests require local `events_test`. They use synthetic dashboard credentials,
transactional records, a temporary disk storage directory removed after the
suite, test email/jobs, and WebMock to reject external Ruby HTTP requests.
WebDriver's localhost traffic is allowed. No production imports or real S3/SMTP
operations are part of the suite.

Known defects have executable `pending` expectations with assessment item IDs;
they still run, and an unexpected pass fails the suite so the pending marker must
be removed when the issue is fixed. They are separate from passing smoke coverage.
Unpublished-event write semantics and monthly-statistics semantics still require
product decisions; the tests do not decide those policies implicitly.

`bin/ci` writes JUnit results to `tmp/test-results/rspec.xml`. Failed system tests
save screenshots under `tmp/screenshots/`; CircleCI retains both. CircleCI deploys
successful `main` builds to Dokku. Security scans and linting remain assessment
follow-ups and are not yet part of `bin/ci`.

## Refresh development data from Dokku

Stop local Rails servers/consoles holding database connections, and ensure
`events_development` exists (`bin/rails db:create` on first setup). You need SSH
and SCP access to the Dokku server, plus `pg_dump`, `pg_restore`, `dropdb`, and
`createdb` compatible with the production PostgreSQL version.

Supply the name of Easy RSVP's linked Dokku **PostgreSQL service**, which can
differ from the app name:

```sh
DOKKU_PG_SERVICE=your-service-name bin/rails db:pull_production
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
| `DOKKU_HOST` | SSH destination; defaults to `root@dokku.kevinbongart.net` |
| `PG_BIN` | Directory containing all four PostgreSQL tools, if automatic discovery selects the wrong version or finds none |
| `CONFIRM_PULL_PRODUCTION` | Set to exactly `events_development` for an intentional noninteractive replacement |

The production database is only exported. The remote temporary dump is removed
after copying; a cleanup failure is reported. Production and pre-import local
archives remain under ignored `tmp/database_backups/`, with directory mode `0700`
and archive mode `0600`. Keep the previous local archive until the import is
verified, then delete unneeded copies containing real user data.

After importing, apply any pending local migrations with `bin/rails db:migrate`.
This task copies database rows only; it does not copy attachment files or isolate
the app's configured S3 bucket and SMTP service.

The import tests use fake commands and never access Dokku or replace a database:

```sh
bundle exec rspec spec/lib/production_database_pull_spec.rb
```

## Engineering and assessment

- [Rails engineering playbook](docs/RAILS_ENGINEERING_PLAYBOOK.md), copied from Bon App
- [Current application and agent reference](AGENTS.md)
- [Codebase assessment and remediation plan](docs/CODEBASE_ASSESSMENT.md)
