# PostgreSQL major upgrade runbook

How to move the production Dokku PostgreSQL service to PostgreSQL 18. Only the
owner runs these commands; agents must not (see AGENTS.md).

## Where things stand

- **Production:** the 2026-09-22 backup was dumped from PostgreSQL **15.1**, a
  2022 release that misses every 15.x security fix since. Version 15 itself is
  supported until November 2027. Confirm the current version in step 1.
- **Target:** PostgreSQL **18.7** (official `postgres:18.7` image). 19.0 has no
  minor release yet. CI runs `cimg/postgres:18.7`.
- **Rehearsal (2026-11-25, PostgreSQL 18.3 on a Mac):** the 2026-09-22
  production archive restored into an empty 18 cluster with no errors in under
  30 seconds. The row counts of all 29 tables matched the archive. The 17
  migrations added since then ran cleanly, and the full test suite passed
  against that cluster.

Plan for 10 to 15 minutes of downtime. The app is stopped while the data is
copied, so no write is lost.

## 1. Check the server

On the Dokku host (`ssh $DOKKU_HOST`), with `SERVICE` set to the value of
`DOKKU_PG_SERVICE`:

```sh
SERVICE=<your DOKKU_PG_SERVICE>
dokku version                                # plugin 2.x needs Dokku 0.35+
dokku plugin:list | grep postgres            # need 1.46.1 or later, see below
dokku postgres:info "$SERVICE" --version     # e.g. postgres:15.1
dokku postgres:links "$SERVICE"              # expect only easy-rsvp
dokku postgres:backup-schedule-cat "$SERVICE" # note any schedule; it is not copied
df -h /var/lib/dokku                         # need at least twice the data size free
```

Both upgrade options need dokku-postgres **1.46.1 or later**. Older plugins
mount the data directory at `/var/lib/postgresql/data`, but PostgreSQL 18
images keep their data under `/var/lib/postgresql`, so a version 18 service
does not start or does not keep its data on the host. Plugins older than 1.32.0
also lack the `--no-restart` flag used below. If the plugin is older, update it
first, then check that the existing service still reports as running:

```sh
sudo dokku plugin:update postgres            # 2.x, on Dokku 0.35 or later
sudo dokku plugin:update postgres 1.48.0     # instead, on older Dokku
dokku postgres:info "$SERVICE"               # status must be running
```

## 2. Back up and prove the backup restores

On your Mac, from the repository:

```sh
bin/rails db:backup_production
```

Before going further, restore that archive (decrypted first, if encrypted) into
a throwaway local database, then delete the database:

```sh
createdb easy_rsvp_restore_check
pg_restore --no-owner --no-acl --dbname=easy_rsvp_restore_check db/backups/<archive>.pgdump
psql -d easy_rsvp_restore_check -c "select count(*) from events"
dropdb easy_rsvp_restore_check
```

Install PostgreSQL 18 client tools now if you do not have them
(`brew install postgresql@18`). After the upgrade, production archives can only
be read by `pg_restore` 18 or newer. `db:backup_production` and
`db:pull_production` pick the newest installed version automatically.

## 3. Record row counts

```sh
dokku postgres:connect "$SERVICE"
```

Paste the query below and keep the output. You will compare it after the upgrade.

```sql
select (select count(*) from events) as events,
       (select count(*) from rsvps) as rsvps,
       (select count(*) from action_text_rich_texts) as rich_texts,
       (select count(*) from active_storage_blobs) as blobs,
       (select max(version) from schema_migrations) as schema_version;
```

## 4. Upgrade

Use option A unless you have a reason not to. It works on any plugin from
1.46.1 (step 1) and does not touch the old service, so a rollback is two
commands.

### Option A (recommended): new service, then switch the link

```sh
NEW="$SERVICE-18"
dokku postgres:create "$NEW" --image-version 18.7

dokku ps:stop easy-rsvp                       # downtime starts
(umask 077 && dokku postgres:export "$SERVICE" > "/tmp/$SERVICE-pre-18.dump")
dokku postgres:import "$NEW" < "/tmp/$SERVICE-pre-18.dump"
dokku postgres:connect "$NEW"                 # run the step 3 query; counts must match

dokku postgres:unlink "$SERVICE" easy-rsvp --no-restart
dokku postgres:link "$NEW" easy-rsvp --no-restart
dokku ps:start easy-rsvp                      # downtime ends
rm -f "/tmp/$SERVICE-pre-18.dump"
```

Unlink the old service before linking the new one. Otherwise the new link goes
into a `DOKKU_POSTGRES_<COLOR>_URL` variable and the app keeps using the old
database. `dokku config:get easy-rsvp DATABASE_URL` must now name
`dokku-postgres-$NEW` (do not paste it anywhere; it holds the password).

A dump and restore does not copy planner statistics. Run `analyze;` in
`dokku postgres:connect "$NEW"` once the app is back.

### Option B: in place, only with dokku-postgres 2.3.0 or later

```sh
dokku postgres:upgrade "$SERVICE" --definition postgres-18 --image-version 18.7 --restart-apps
```

Caveats:

- **Never run `postgres:upgrade --image-version 18.7` alone or on a plugin
  older than 2.3.0.** Older plugins only swap the image. PostgreSQL 18 then
  refuses to start on the version 15 data directory, and the site is down.
- The plugin runs `pg_upgrade` from the `tianon/postgres-upgrade:15-to-18`
  image. That needs free disk equal to the data size. `--restart-apps` stops the
  app while the data is copied. A failed upgrade puts the service back on 15.
- After a successful upgrade, setting the version back does not undo it. The
  only rollback is restoring the step 2 backup into a new version 15 service.
- The old data stays in a `data.<definition>.<timestamp>` directory until you
  run `dokku postgres:upgrade-cleanup "$SERVICE"` (step 7).

## 5. Verify

- `curl -fsS https://<your domain>/up` returns 200.
- The home page, an existing public event page and its organizer page load.
- The step 3 query on the new database returns the same numbers, and
  `select version();` reports 18.7.
- `dokku logs easy-rsvp --tail` and Honeybadger show no database errors for
  15 minutes.
- On your Mac, after updating `DOKKU_PG_SERVICE` (step 6),
  `bin/rails db:backup_production` succeeds.

## 6. After the upgrade

- Option A: set `DOKKU_PG_SERVICE=$SERVICE-18` in your local `.env`. Re-create
  any backup schedule noted in step 1 on the new service, and re-run
  `postgres:expose` if the old service was exposed.

## 7. Rollback and cleanup

Option A rollback, while the old service still exists:

```sh
dokku ps:stop easy-rsvp
dokku postgres:unlink "$NEW" easy-rsvp --no-restart
dokku postgres:link "$SERVICE" easy-rsvp --no-restart
dokku ps:start easy-rsvp
```

Events and RSVPs written to the new database after the switch are lost on
rollback: a PostgreSQL 18 dump cannot be restored into 15. Decide within the
maintenance window if you can.

Once production has run cleanly for a week:

- Option A: `dokku postgres:destroy "$SERVICE"` (it asks you to confirm).
- Option B: `dokku postgres:upgrade-cleanup "$SERVICE"`.
