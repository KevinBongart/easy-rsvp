# Easy RSVP — Codebase Assessment and Remediation Plan

Assessed **2026-09-08**, branch `main`, commit `38413a5`, including the existing
uncommitted playbook/agent documentation, README/environment additions, and
production-database pull implementation/specs from the preceding task.

Status: **assessment and Phase 0 coverage complete; original pending regressions fixed; broader remediation remains**. This replaces the
initial assessment brief. Standards: [Rails Engineering Playbook](RAILS_ENGINEERING_PLAYBOOK.md).
Application reference: [AGENTS.md](../AGENTS.md).

## Modern Rails assets and rich text — 2026-09-14

The asset portion of Phase 5.2 began on `codex/modern-rails-assets-action-text`.
Sprockets, SassC, CoffeeScript, Rails UJS, and Turbolinks were replaced by
Propshaft, Turbo, and Stimulus. Bootstrap initially remained at 4.6.2 as a
compatibility step; the later Bootstrap 5 follow-up moved its JavaScript into
the npm/esbuild bundle and its Sass into dartsass-rails.

Event descriptions now use Action Text. Existing `events.body` values are
backfilled into `action_text_rich_texts`; Rails' Trix and Action Text assets load
from the locked gems, and Active Storage handles direct uploads. The custom Trix
download/esbuild script, generated editor assets, inline ClipboardJS setup, and
custom editor upload transport are removed. Small Stimulus controllers cover
copying, RSVP form reveal, accepted image types/size, and visible upload failure
recovery. A small direct-upload controller enforces declared image types and a
1-byte-to-10-MB range before creating a blob or storage URL. It cannot inspect
direct-to-storage bytes; byte-level policy, ownership, expiry, and rate controls
remain follow-ups. The now-unused public `ImageUploadsController` route is
removed; legacy `ImageUpload` records remain readable. The layout emits Subresource
Integrity-protected module preload links
and tracks the compiled stylesheet for Turbo reloads.

The initial migration retained `events.body` while production moved to Action
Text. After that compatibility period, a later migration removed the legacy
column and its temporary `ignored_columns` declaration. The removal repairs
missing Action Text rows and preserves divergent legacy values in
`legacy_event_body_conflicts` rather than guessing which version is newer.
Rich-text images use original blob URLs, avoiding an undeclared ImageMagick/libvips
runtime dependency and first-render variant processing.

The Firefox suite covers Turbo navigation, rich-text creation/editing/paste,
image persistence after save/reload/edit, invalid-file retry, direct-upload
network/server failure recovery, Turbo validation errors, Bootstrap modal
transitions and snapshot cleanup, clipboard behavior, and Turbo delete links.
`bin/ci --seed 70291` passes both security
scans, eager loading, npm and import-map audits, Propshaft compilation, and **203 examples with
0 failures and 0 pending**. The Action Text migration also passes a test-database
down/up cycle. Upload ownership/expiry remains deferred under 2.4, and Bootstrap
5 remains the unfinished part of 5.2.

## Bootstrap 5 and JavaScript bundling — 2026-09-15

Bootstrap is updated to 5.3.8 with its official Simple Form wrappers and renamed
markup/data attributes. jQuery, legacy Popper, importmap-rails, and all vendored
JavaScript copies are removed. jsbundling-rails now invokes esbuild through the
standard `assets:precompile` hook; the single locked npm graph owns Turbo,
Stimulus, Trix, Action Text, Bootstrap, and Bootstrap's current Popper peer.
Only Bootstrap's Alert and Modal plugins enter the application bundle.

The layout serves integrity-protected, Turbo-tracked CSS and JavaScript.
`bin/dev` runs the Dart Sass and JavaScript watchers, so SCSS changes rebuild
automatically without manual asset tasks. `bin/ci` installs and audits npm once
before Rails builds both entrypoints and precompiles all assets. The official
Stimulus controller manifest and Simple
Form Bootstrap 5 template replace import-map loading and the legacy wrappers.
Modal controls now have Bootstrap 5 attributes, unique form field IDs and an
accessible label; Trix editors have explicit accessible names.

## RSVP response constraint validation — 2026-09-09

The production-derived development database contained 88,330 RSVPs and no null
or unsupported response values. The existing `rsvps_supported_response` check is
now validated for historical rows as well as enforced for new writes. No response
data was rewritten or coerced. Validation completed locally in 18 milliseconds.

## Dependency security remediation — 2026-09-09

Rails is updated to 8.1.3.1 and rubyzip to 3.6.0. The unused
`rails_real_favicon` generator was removed because it pins rubyzip to 2.x;
all generated favicon assets remain. Bundler-audit and Brakeman are locked
development/test dependencies and run in `bin/ci`, including CircleCI.
The updated audit reports no vulnerable gem matches; Brakeman reports no
security warnings. Vendored JavaScript and runtime patching remain separate.

## Pending-regression remediation — 2026-09-08

Starting from merged PR #868 (`1e516fd`), the 19 pending expectations were removed
one defect group at a time in priority-ordered commits. All now pass. The fixes are:

1. P1 upload validation: required PNG/JPEG/GIF/WebP content detected from file bytes,
   with a 10 MB limit and no upload record created for rejected input.
2. P1 RSVP request guards: missing/non-string submit values, malformed nested
   parameters, and absent ownership sessions receive controlled responses.
3. P1 response integrity: model inclusion and a PostgreSQL check constrain new
   writes, including writes that bypass model validation.
4. P1 event deletion: dependent RSVP destruction runs within the event transaction.
5. P1 mail links: production used the configured `DOMAIN` and HTTPS. The dormant
   email feature was later removed entirely under 3.3.
6. P1 Trix uploads: one document listener, local XHR state, and visible recovery for
   rejected files, network errors, timeouts, and malformed JSON responses.
7. P2 publication and session state: unpublished guest writes are blocked;
   successful deletion removes only the relevant ownership ID and drops empty keys.
8. P2 statistics: yearly/monthly counts and projections use creation timestamps;
   monthly numeric counts are computed once and the UI labels creation metrics.

Validation: `CI=true bin/ci --seed 56913` passes eager loading, asset compilation,
and **177 examples, 0 failures, 0 pending** (13.46 seconds of RSpec execution).
The added Firefox coverage includes real Turbolinks navigation, a real rejected
upload followed by a successful upload, and injected transport failures followed
by retries through the actual endpoint/storage. The database migration was tested
up/down/up only against `events_test`. No production data was accessed or changed.

The response constraint was initially added as `NOT VALID` so new writes were
protected without scanning, rewriting, or silently coercing historical responses.
Item 1.4 was completed after the aggregate review described above. Upload
ownership/expiry, direct-upload route policy, and request-level abuse limits remain
deferred in 2.4. Other unchecked assessment items remain separate work.

Earlier sections below are dated evidence snapshots, including their historical
pending counts and descriptions of defects before these fixes.

## Creation-date policy and Phase 0 completion — 2026-09-08

The owner confirmed that dashboard statistics measure when events were created.
Yearly totals, monthly history/current counts, and projections must use `created_at`;
rescheduling an event must not rewrite growth history. Six additional presenter
examples deliberately separate creation timestamps from scheduled dates: yearly
assignment, current-month inclusion/exclusion, December/January history, exact
creation-month boundaries, rescheduling invariance, and monthly projections.

The yearly example passes. The other five first failed with observed incorrect
counts and are executable pending regressions for Phase 4.2. The suite now has
**156 examples and 19 pending regressions**. `CI=true bin/ci --seed 56913`
passes eager loading, asset compilation, and all 156 examples with zero failures
(11.73 seconds of RSpec execution). All four Phase 0 checklist items are
complete as coverage tasks. The approved publication/statistics policies are
recorded; their application fixes and other remediation remain outstanding.

## Unpublished-event policy follow-up — 2026-09-08

The owner confirmed that unpublished events must block guest RSVP additions and
deletions, while organizer editing remains available. Six request examples now
cover blocked guest additions, blocked deletion by a previously authorized guest,
organizer event editing, organizer RSVP update/delete, and guest additions after
republishing. Both denied guest-write tests first failed with actual record
creation/deletion; they are now executable pending regressions for Phase 1.5.
The other four pass. `CI=true bin/ci --seed 56913` passes eager loading, assets,
and **150 examples, 0 failures, 14 pending** (14.68 seconds of RSpec execution).
Phase 0.1 is complete as a coverage task; Phase 1.5 enforcement is still outstanding.
At this stage Phase 0.3 remained open for the dashboard policy; the later
creation-date follow-up above completes it.

## Phase 0 completion work — 2026-09-08

The follow-up adds 12 examples, for **144 examples with 12 known pending
regressions**. New coverage exercises blank/array/hash submit values, missing
name parameters, stale and explicitly empty ownership sessions, HTTPS email
links, SMTP delivery failure, and the actual production mail configuration.
The configuration test evaluates the production file against an isolated
application configuration; it does not boot production or use SMTP/S3.

Three non-string submit cases reproduce the existing `NoMethodError` in 1.2.
The production configuration test reproduces the `example.com` override in 1.6.
These four new pending expectations were added only after observing the failures.
The mail delivery failure test characterizes the current exception propagation,
while asserting unchanged event data and no recorded delivery; it does not claim
that the current UI offers graceful recovery.

`CI=true bin/ci --seed 56913` passes eager loading, asset compilation, and
**144 examples, 0 failures, 12 pending** (12.21 seconds of RSpec execution).
Hosted execution of the earlier suite exposed an obsolete Chrome repository
signing key in the browser image and timestamp precision differences between
Ruby and PostgreSQL. CI now uses the Ruby/Node image with Firefox installed by
the browser orb. No-mutation assertions compare reloaded persisted values on
both sides, including timestamps. CircleCI build
[1837](https://circleci.com/gh/KevinBongart/easy-rsvp/1837) passed on `eaa2ed1`,
including eager loading, assets, all 144 examples, and artifact upload.

At this point both policy questions were pending. The later unpublished-event
and creation-date follow-ups above record both approved rules and complete 0.1/0.3.

## Branch preparation follow-up — 2026-09-08

Before opening the PR, the branch was rebased onto `origin/main` at `cffb25e`.
That includes 44 upstream dependency commits, including Rails 8.1.3. The original
assessment and dependency audit below describe `38413a5`; their locked versions
and advisory counts must not be treated as the current branch's dependency state.
The application behavior findings still apply because upstream changed only the
Gemfile and lockfile.

On this updated branch, `bin/ci --seed 56913` passes eager loading, asset
compilation, and **132 examples, 0 failures, 8 pending** (13.19 seconds of RSpec
execution). A fresh bundler-audit scan using the same advisory database reports
**two gem/advisory matches**: Active Storage 8.1.3 (CVE-2026-66066; patched in
8.1.3.1) and rubyzip 2.4.1 (CVE-2026-85396; patched in 3.4.0). The latter is also
used by development tooling; assess dependency constraints before upgrading.
These remain version matches, not verified exploitability. The vendored Trix
assessment is separate and still applies. The original 75-match report is retained
as historical evidence.

## Test-harness follow-up — 2026-09-08

The initial assessment below remains a dated baseline. The subsequent test work
adds 117 examples, bringing the suite to **132 examples** across these layers:

| Layer | Examples | Coverage |
| --- | --- | --- |
| Models | 28 | Event identity/validation/deletion, RSVP ownership/validation/foreign key, disk attachments and purge |
| Presenter units | 9 | Empty counts, formatting, month boundaries, leap years, extrapolation, no hidden queries |
| Mailers | 4 | Recipients, subject, organizer/public links, local delivery |
| Requests | 58 | Public and organizer CRUD, token isolation, Basic Auth, privacy/XSS samples, email, upload/download bytes, query count |
| Integration | 2 | Independent organizer/guest sessions and real CSRF enforcement |
| Existing features | 3 | Creation/RSVP/publication journey and dashboard; now use a fixed clock |
| System | 12 | Four Rack Test form flows, seven passing Firefox smoke cases, one known upload-lifecycle regression |
| Database utility units | 16 | Export/restore guards/recovery and literal command execution/error handling |

Eight tests execute desired behavior as explicit `pending` regressions: event
cascade deletion (1.1), missing submit/session state (1.2, two tests), session
cleanup (1.3), supported RSVP responses (1.4), upload-listener accumulation (1.7),
and attachment presence/type validation (2.4, two tests). An unexpected pass
fails RSpec, requiring removal of the marker when a fix lands. These tests do not
silently accept the defects as correct behavior.

Firefox uploads use a real native file-drop event, actual Trix handlers, the Rails
upload endpoint, and local Active Storage. Tests check decoded file bytes,
browser image loading after save/reload, and image preservation after editing.
Trix's public editing API is used for deterministic text insertion, as in Rails'
rich-text system helper. Clipboard, modal update/delete/close, and UJS guest
deletion also have browser coverage. Firefox specs enable real CSRF protection
so upload/UJS token handling is covered. The harness waits for Bootstrap's public
`shown.bs.modal` event instead of clicking during its opening animation.

Test records are transactional; storage has a temporary per-process disk root;
mail/jobs use test adapters; external Ruby HTTP is blocked, with localhost allowed
for WebDriver. Asset resolution uses current source to avoid stale compiled
manifests masking regressions. The new `bin/ci` and CircleCI job run eager loading,
asset compilation, and all tests, retaining JUnit output and failure screenshots.

Validation: `bin/ci --seed 18467` passes with **132 examples, 0 failures, 8
pending**, in 15.21 seconds of RSpec execution (0.91 seconds loading), plus
successful eager loading and asset compilation. A second randomized order
(`bundle exec rspec --seed 56913`) also passed all 132 examples with the same
eight pending regressions. The final `bin/ci --seed 56913` run also passed
with real CSRF protection enabled in Firefox. A mutation check temporarily
renamed the Trix upload event handler: the real Firefox upload test failed at its
persisted-image assertion, and the application source was restored unchanged.
CircleCI YAML parses locally; online `circleci config validate` was attempted but
rejected the existing API token. Hosted execution has not been verified.

The later follow-ups above complete all Phase 0 coverage, including the
owner-approved publication and dashboard rules. Production mail-host and delivery-failure coverage
has since been added. Phase 7.1 has local/hosted test parity and browser
artifacts implemented; scans and lint remain separate follow-ups. No product
controllers, models, views, or JavaScript were changed by this test expansion.

## Executive summary

The application is small and understandable: ten controllers and four model files
(including base classes) total 295 lines. Event creation, rich-text saving, RSVP
creation, and publication toggling have working paths. Organizer mutations match
both event ID and token, nested RSVP lookups use event associations, and sampled
denied-access requests preserve data. There is no architectural reason to turn
this into a large service framework or add accounts.

Confidence is much lower than the green suite suggests. **Only three examples
exercise the product**; twelve test the newly imported database utility. None of
the committed tests execute JavaScript. Local probes exposed several failures
that the existing suite does not observe:

- Deleting an event with RSVPs raises a foreign-key exception.
- RSVP requests without a submit value or session entry raise exceptions;
  successful deletion leaves stale ownership IDs in the session.
- Organizer updates accept unsupported responses, which disappear from the
  public response groups. Unpublished events still accept direct RSVP writes.
- Production mail configuration overrides `DOMAIN` with `example.com`.
- Attachment handlers accumulate on repeated Turbolinks load events.

Dependencies need prompt attention: the lockfile audit found **75 distinct
advisory matches across 22 gems**. The vendored Trix 0.11.2 is outside that audit
and falls in upstream XSS-affected ranges. These are version matches, not a claim
that all reported vulnerabilities are exploitable through this application.

The best sequence is a small test-harness improvement, focused correctness and
security patches, and then measured cleanup/modernization. Security patching
should not wait for the entire frontend migration or every lower-priority item.

### Scorecard

Grades are qualitative judgments of the reviewed evidence, not coverage metrics.

| Dimension | Grade | Assessment |
| --- | --- | --- |
| Security/privacy | D+ | Good sampled token/association boundaries; private tokens in request logs, unrestricted public uploads, substantial patch debt |
| Maintainability | B− | Small controllers/models; some repeated parsing, dead scaffolding, and ambiguous controller names |
| Modularity | B− | Clear basic layers; upload lifecycle has no event owner and presenter owns repeated aggregations |
| Evolvability/data integrity | C− | Foreign key protects data but breaks event deletion; response constraints are incomplete |
| Rails conventions | C+ | Resources, strong parameters, association scoping; Rails 5.2 defaults and legacy asset stack remain |
| Test speed | A | Full 15-example suite executes in 1.21 seconds locally |
| Test coverage | D | Three product examples; no committed model/request/presenter/browser coverage |
| Frontend/accessibility | C− | Basic Firefox flows work; listener accumulation and inaccessible/fragile markup need attention |
| Documentation/agent readiness | B | Prior task added useful current guidance; operational gaps and feature decisions remain |
| Dependencies/runtime | D | Locked Rails/Rack and many transitive dependencies match advisories; vendored assets bypass audits |
| CI/operations | C− | Working RSpec/deploy configuration; no scans, browser suite, local CI aggregate, or health route |

## Evidence and limitations

### Checks performed

| Check | Result |
| --- | --- |
| `bundle check` | Dependencies satisfied in the preceding task; no dependency changes since |
| `RAILS_ENV=test bundle exec rspec --seed 18467` | 15 examples, 0 failures; 1.21 s execution, 0.61 s loading |
| `RAILS_ENV=test bin/rails zeitwerk:check` | Pass |
| `RAILS_ENV=test bin/rails assets:precompile` | Pass; writes ignored local assets |
| Routes inspection | Actual public, organizer, dashboard, Active Storage routes reviewed; `/up` absent |
| Targeted request/model/presenter/log probes | 15 observations reproduced, including denied-access controls and failure paths |
| Headless Firefox via Selenium 4.35.0 | Root/editor load, rich-text save, public RSVP and RSVP-again work; repeated lifecycle event reproduces upload duplication |
| Desktop/narrow screenshots | Creation page inspected at actual 1280 px and 450 px widths; no horizontal overflow there |
| Dashboard scaling probe | Two SQL queries at both sizes; row instantiation and time grow with total data, despite pagination |
| Local production-config boot | With a local test DB URL and dummy secret/auth configuration, `DOMAIN=assessment.example` still yields mail host `example.com` |
| Brakeman 8.0.4 | One medium-confidence lifecycle warning; no other reported code warnings |
| bundler-audit 0.9.3 | Fails: 159 raw results, 75 distinct gem/advisory pairs, 22 gems |

Brakeman and bundler-audit were already installed under Ruby 4.0.3 and invoked
with `RBENV_VERSION=4.0.3`; the app/tests ran on pinned Ruby 3.3.4. Their presence
on this machine does not make them repository dependencies or CI checks.
Brakeman's lifecycle warning says Rails support ends 2026-10-07; treat that as the
scanner's warning, not an independently verified deadline. The
[upstream maintenance policy](https://guides.rubyonrails.org/maintenance_policy.html)
is authoritative. Patch debt is independently established by advisories below.

The advisory database was updated to commit `e7179ad`. Multiple lockfile platform
variants inflate the raw result count; [the deduplicated audit](assessment/2026-09-08-dependency-audit.md)
records every matched gem, advisory, version, and patch range. Development/test
packages and unused installed framework components are included. No exploitability
claim is inferred from the count alone.

Temporary probes, scan output, screenshots, and timings remain under ignored
`tmp/codebase_assessment/`. Request probes used transactions against `events_test`;
the two synthetic browser events and their RSVPs were removed afterward. The
observation specs assert current behavior, including defects; they are evidence,
not regression acceptance tests to copy unchanged into the permanent suite.

No production database, Dokku server, external email delivery, or S3 upload was
used. The local production boot caused the AWS SDK to attempt instance-metadata
credential discovery without credentials; it failed, and no S3 operation was
performed. For future offline production-config checks, set
`AWS_EC2_METADATA_DISABLED=true` and dummy S3 credentials as appropriate.

This was not a live penetration test, full accessibility audit, migration replay,
or hosted CI/deployment verification. Firefox's minimum window width produced
450 px, so 320–390 px phone layouts still need inspection. Screenshots did not
cover every dense/error state. No line-coverage percentage was measured. Lint
configuration does not exist, so no arbitrary default-style report is presented
as an established project check.

### Measured dashboard behavior

`Admin::EventsController#index` loads all events with all associated responses,
then paginates an array. Instrumentation wrapped the complete authenticated
request after a warm-up. Two synthetic browser events/RSVPs existed at the time.

| Added events / RSVPs | Event objects loaded | RSVP objects loaded | SQL queries | Request time |
| --- | --- | --- | --- | --- |
| 10 / 30 | 12 | 32 | 2 | 0.0170 s |
| 1,000 / 3,000 | 1,002 | 3,002 | 2 | 0.5539 s |

These are single local observations, not production capacity estimates. They
prove unbounded row loading, not an N+1 problem. Preserve intentional preloading
while moving listing/sorting/counting into bounded database operations.

## How to use the plan

Each unchecked item is proposed work, not an already implemented change.
**P1** means address promptly because it causes failures, breaks a trust boundary,
or leaves relevant known patch exposure. **P2** is important follow-up. **P3** is
low-risk cleanup. Add regression tests for the desired behavior before each fix.
Do Phase 0's relevant tests before refactoring, but patch known vulnerabilities
as soon as the focused smoke path can validate the update.

Preserve the accountless product and its separate public/session, organizer-token,
and dashboard-auth boundaries. No Easy RSVP security-risk acceptance has been
provided; Bon App's accepted risks do not transfer.

## Phase 0 — Test harness first

- [x] **0.1 P1 — Cover access boundaries and malformed requests.** Covered:
  wrong organizer tokens, cross-event RSVP update/delete, dashboard authentication,
  empty/missing/stale ownership state, unsupported/missing/non-string submit values,
  and missing name parameters, with no-mutation assertions. The approved unpublished
  rule now has pending guest-write regressions and passing organizer/republish tests.

- [x] **0.2 P1 — Add a small real-browser suite.** Rack Test covers fast forms;
  Selenium/headless Firefox covers editor save/upload, clipboard, RSVP-again,
  organizer response modals, and UJS deletion. An executable pending test reproduces
  upload-handler duplication before its Phase 1 fix.

- [x] **0.3 P2 — Cover model, presenter, and mail contracts.** Covered:
  event deletion with/without responses, response inclusion, date boundaries and
  extrapolation, hidden-name rendering, configured HTTPS mail URLs, the production
  mail-host override, blank/invalid attachments, and failed mail delivery. Six
  creation-date examples separate scheduled dates from creation timestamps,
  including year/month boundaries, rescheduling, and projections. Five reproduce
  the monthly calculation defect as pending expectations for Phase 4.2.

- [x] **0.4 P2 — Make the harness deterministic and self-contained.** Fixed clocks,
  synthetic Basic Auth, randomized order, temporary disk storage, test mail/jobs,
  blocked external Ruby HTTP, and `bin/ci` are implemented. Persisted before/after
  snapshots avoid platform-dependent timestamp precision mismatches.

## Phase 1 — Correctness and proven bit-rot

- [x] **1.1 P1 — Repair event deletion.** Completed in the remediation above; original finding follows. `Event` has `has_many :rsvps` without a
  dependent policy (`app/models/event.rb:4`), while `rsvps.event_id` has a foreign
  key (`db/schema.rb:73`). `OrganizerEventsController#destroy` calls
  `@event.destroy`. A token-authorized DELETE of an event with one RSVP raises
  `ActiveRecord::InvalidForeignKey`; an empty-event path alone misses the defect.
  Define the intended cascade, implement it transactionally, and test both cases
  and unauthorized deletion. This route exists even though no event-delete
  control is currently rendered.

- [x] **1.2 P1 — Handle malformed RSVP submissions and absent session ownership.** Completed in the remediation above; original finding follows.
  `app/controllers/rsvps_controller.rb:5` calls `downcase` on `params[:commit]`
  without validating its presence/type. Missing `commit` raises `NoMethodError`.
  Lines 23–25 pass a missing session entry into `in?`, raising `ArgumentError`
  on a sessionless DELETE of an existing RSVP. Reject malformed input with a
  controlled response; treat a missing ownership list as empty and preserve the
  response. Test nil, wrong-shaped values, unsupported answers, and denied deletes.

- [x] **1.3 P2 — Persist session cleanup after RSVP deletion.** Completed in the remediation above; original finding follows. Line 27 reassigns
  `event_session -= [@rsvp.hashid]` but never writes it back to `session`.
  The record disappears while the cookie's ownership array retains its hashid.
  Repeated use grows stale session data. Store the reduced array or delete an
  empty key; test both database state and subsequent session contents.

- [x] **1.4 P1 — Validate response membership.** Model validation and the check
  constraint protect new writes. An aggregate review found zero invalid responses
  among 88,330 production-derived rows, and the constraint is now validated without
  modifying historical data. Original finding: `app/models/rsvp.rb:13` only
  validates response presence. The organizer endpoint permits `response`
  (`app/controllers/organizer_rsvps_controller.rb`). A PATCH with `unexpected`
  persists successfully; the public view only groups yes/maybe/no and omits
  that guest (`app/views/events/show.html.erb:40`). Add inclusion validation,
  a safe data cleanup/migration, and a database check constraint; test model,
  request, and direct-database writes. Do not silently coerce existing bad data.

- [x] **1.5 P2 — Enforce the approved unpublished-event write policy.** Completed in the remediation above; original finding follows. Public
  display checks `published?` (`app/controllers/events_controller.rb:34`), but
  `RsvpsController#set_event` does not. The owner confirmed that unpublishing blocks
  guest creation and deletion of RSVPs, including previously session-owned responses.
  Organizer event editing and RSVP management must remain available. The two
  pending request regressions reproduce actual writes; implement the guard and
  remove their pending markers. Republishing must restore guest RSVP access.

- [x] **1.6 P1 — Fix production email link hosts.** Completed in the remediation above; original finding follows.
  `config/environments/production.rb:60` hardcodes `example.com`, overriding
  `config/application.rb`'s `DOMAIN`. A local production boot confirmed this
  even with a nonempty synthetic `DOMAIN`. `UserMailer` renders both organizer
  and guest URLs using that host. Configure the intended HTTPS host and add a
  configuration/message-body regression test. The email endpoint remains live,
  although the current organizer page has no email form and the feature test's
  email journey is commented out; decide whether to restore that feature or
  remove the unused endpoint in a separate product decision. The feature and its
  configuration were later removed under 3.3.

- [x] **1.7 P1 — Register one attachment handler per document lifecycle.** Completed in the remediation above; original finding follows.
  `app/assets/javascripts/trix_attachments.js:37` adds a document listener inside
  every `turbolinks:load`. In Firefox, three additional load events followed by
  one synthetic attachment event triggered **four upload sends**, intercepted
  before network/storage access. Register once or clean up explicitly; test
  repeated real navigation and one upload request. Scope `xhr` locally (line 15
  currently assigns a global), handle network/non-2xx/invalid-JSON failures, and
  give users a recoverable error instead of a stuck attachment.

- [x] **1.8 P3 — Remove verified dead scaffolding and unused dependencies.**
  Removed `Rsvp#session_key`, the empty `ApplicationHelper` and `EventsHelper`,
  the unused `ApplicationJob` base, and the stray Puma Solid Queue plugin. The
  generated `events.scss` stub was already removed during the asset migration;
  Jbuilder and Octicons were removed with the dormant email feature. Retained
  the live `Admin::EventsHelper`, framework Active Job configuration, and Trix.

## Phase 2 — Security and privacy

- [x] **2.1 P1 — Patch relevant dependency exposures and add audit coverage.**
  Completed through the dependency and runtime upgrades. The lockfile now uses
  Rails 8.1.3.1, Rack 3.2.6, Puma 8.0.2, Loofah 2.25.2, and Nokogiri 1.19.4.
  `bin/ci` refreshes and runs Bundler Audit, Brakeman, and npm audit as required
  gates before compiling assets and running the full suite. The
  [deduplicated audit](assessment/2026-09-08-dependency-audit.md) remains a
  historical baseline rather than a description of the current lockfile.
  Original finding: Rails 8.0.2.1 predates the
  [March security patches](https://rubyonrails.org/2026/3/23/Rails-Versions-7-2-3-1-8-0-4-1-and-8-1-2-1-have-been-released)
  and [July variant-processing patch](https://rubyonrails.org/2026/7/29/Rails-Versions-7-2-3-2-8-0-5-1-and-8-1-3-1-have-been-released).
  Rails 8.0.5.1 is a verified patched release on the current minor line; choose
  the current compatible release at implementation time. Rack 3.2.1 matches
  [multipart memory-exhaustion advisories](https://github.com/rack/rack/security/advisories/GHSA-p543-xpfm-54cp),
  relevant to this app's public multipart endpoint. No large-payload attack was
  run. Check proxy limits before making deployment-level exploitability claims.
  Do not call every installed gem an exposed production feature: Action Cable,
  Action Text, IMAP clients, and development tooling have different reachability.

- [x] **2.2 P1 — Replace/update the unaudited vendored editor.** Completed
  2026-09-09 with locked Trix and DOMPurify dependencies, build-time generation,
  npm audit coverage, and native Firefox paste/upload regressions. Generated
  editor assets are ignored; ordered Node and Ruby buildpacks make the production
  build reproducible. Original finding:
  `vendor/assets/javascripts/trix.js:2` declares Trix **0.11.2**. It falls within
  [CVE-2024-34341's affected range](https://github.com/basecamp/trix/security/advisories/GHSA-qjqp-xr96-cj99),
  which covers script execution through crafted pasted content. Public and
  organizer views use Rails `sanitize`, which is a useful display boundary but
  does not fix execution inside an old editor. No browser exploit was attempted.
  Move to a maintained, pinned version with editor/paste/upload tests; upstream's
  [July 2026 advisory](https://github.com/basecamp/trix/security/advisories/GHSA-53g2-mvcc-q9x3)
  identifies 2.1.18 as a patched baseline for that issue. Audit vendored clipboard
  2.0.0 too; no specific clipboard vulnerability was established here. Empty npm
  dependencies mean npm/Dependabot cannot track these checked-in JS copies.

- [ ] **2.3 P1 — Keep organizer credentials out of URL logs.** Application
  logger and Honeybadger notice redaction are implemented and covered by the
  suite. Proxy
  rollout and external collector verification remain; see
  [Organizer link privacy](ORGANIZER_LOG_PRIVACY.md). Original finding:
  Routes embed the credential in the path (`config/routes.rb:4`), and Rails'
  request-start log includes that path verbatim. A local logger probe found the
  synthetic token even though parameter filtering includes `:token`. Redact these
  path segments in application, proxy, and error-monitoring logs, or plan a
  credential exchange/session design while preserving shareable organizer links.
  Prove redaction with synthetic tokens and review logging configurations. Merely
  adding another filtered parameter does not fix raw path logging.

- [ ] **2.4 P1 — Bound and own public uploads.** Browser checks and the
  direct-upload controller enforce declared PNG/JPEG/GIF/WebP types and a
  1-byte-to-10-MB range; storage verifies the signed byte length and checksum.
  Direct upload cannot byte-sniff content before it reaches storage. The owner
  deferred ownership/expiry and purge scheduling on 2026-09-09. Byte-level policy,
  request-level abuse controls, and lifecycle remain separate follow-ups.
  Original finding:
  `ImageUploadsController#create` permits any file and `ImageUpload` has no
  presence/type/size validation. A public JSON upload of a plain text file returned
  200 and persisted it. The app also exposes Rails direct-upload routes. Define
  file types and limits, configure request-size/rate controls where appropriate,
  and scope upload creation to the intended event-creation capability. Cover
  invalid/oversized/blank files without exercising S3. ImageUpload rows have no
  event association, so abandoned uploads and deleted events have no coherent
  attachment cleanup path; add an ownership/expiry design before scheduling purge
  work. Avoid purging production blobs based only on an imported local database.

- [ ] **2.5 P2 — Review abuse and browser policies against the actual product.**
  No app-level throttling exists for event creation, public RSVPs, Basic Auth,
  uploads, or organizer-link mail. CSP and permissions-policy files are commented
  templates. Define proportionate controls and test them; inspect actual reverse
  proxy limits before claiming they are absent in production. Keep public creation
  accountless. No password-policy or token-entropy redesign is justified merely
  by copying Bon App's review categories.

## Phase 3 — Documentation and operational clarity

- [x] **3.1 P2 — Close onboarding and feature-documentation gaps.** The README
  now gives a `bin/setup` first-run path, states that no seeds or environment
  variables are needed for the basic local flow, and maps dashboard, storage,
  monitoring, deployment, database-utility, browser, and runtime settings. It
  documents the request-derived canonical host, local disk storage, test command,
  event and RSVP deletion rules, unpublishing behavior, creation-date dashboard
  semantics, attachment controls, and the absence of email delivery. AGENTS now
  requires an independent final-diff review for substantive pull requests while
  retaining a narrow exception for routine automated dependency-only updates.

- [x] **3.2 P1 — Isolate development storage and email.** Development uses a
  dedicated disk root; imported `amazon` blobs resolve to the same local disk
  service, preventing remote reads and purges. The unused email feature and its
  delivery configuration were later removed under 3.3. A
  separate-environment regression proves external credentials and endpoints are
  ignored. Existing imported files require an explicitly authorized local copy.
  Original finding:
  `config/environments/development.rb:32` selects `:amazon`; production also uses
  that service, whose bucket is fixed in `config/storage.yml`. SMTP delivery is
  enabled in `config/application.rb`. The README now warns about these existing
  effects, but ordinary development should default to disk/local email capture.
  Imported blobs retain a `service_name`, so changing only the default service
  does not guarantee isolation of restored records. Specify a safe local-copy
  policy and verify it without writing to real S3 or SMTP.

- [x] **3.3 P2 — Remove organizer-link email delivery.** The app did not expose
  or use this dormant flow, so its disabled route, controller, mailers, templates,
  Action Mailer configuration, environment variables, direct mail dependencies,
  and obsolete tests were removed. A future email capability should be introduced
  as a deliberately configured and tested product feature.

## Phase 4 — Architecture, duplication, and data integrity

- [x] **4.1 P2 — Bound dashboard work in SQL.** The listing is now paginated as
  an Active Record relation before rows are instantiated. PostgreSQL computes
  each displayed RSVP count and count-based ordering, with event ID as a stable
  tie-breaker; the view never loads RSVP records. Chart totals, oldest creation
  date, yearly/monthly buckets, and current-month daily counts use bounded SQL
  aggregates over `created_at`. Request coverage checks page bounds, event and
  RSVP instantiation, deterministic ordering, displayed counts, and constant
  query count as off-page data grows.

- [x] **4.2 P2 — Use creation timestamps consistently for dashboard counts.** Completed in the remediation above; original finding follows.
  `Admin::EventStats#yearly_counts` groups by `created_at.year` (line 29), but
  `count_events_in_month` uses the event's scheduled `date` (line 78).
  A January-created, September-scheduled event counts as a September event.
  The "so far" extrapolation then scales the entire scheduled-month count by
  elapsed days, including future events. The owner approved creation metrics:
  use `created_at` for all buckets/projections and label the displayed counts
  accordingly. Remove the five pending Phase 0.3 markers as the fix lands. Keep numeric counts numeric until formatting; avoid parsing formatted
  strings back into numbers. Cache or aggregate repeated monthly calculations
  within one presenter instance rather than scanning repeatedly.

- [x] **4.3 P2 — Consolidate parsing without merging authorization contexts.**
  `ApplicationController#event_hashid_from_param` now owns extraction of the
  hashid from an event's slugged public parameter. Public and organizer
  controllers share only that parser; organizer-token matching remains in each
  authorization boundary. The `Admin` namespace now belongs only to the
  site-wide HTTP Basic dashboard through `Admin::EventsController`, which applies
  its own authentication without an otherwise-empty parent class. Separately named
  `Organizer*Controller` classes authorize creator actions with the event's private
  token. Existing negative request coverage continues to prove wrong
  credentials, cross-event tokens, and unrelated RSVP IDs cannot cross either
  boundary.

- [x] **4.4 P2 — Tighten persisted invariants deliberately.** The current local
  production-derived database has no null event references, null/blank RSVP names,
  null publication states, or duplicate organizer tokens. New writes are first
  protected by unvalidated checks; a separate migration validates historical rows
  without rewriting them, and a final migration makes `rsvps.event_id`,
  `rsvps.name`, and `events.published` non-null. A retained database check rejects
  blank and whitespace-only names. Migration regressions prove invalid historical
  data stops validation rather than being coerced. The existing foreign key and
  supported-response check remain. No unique organizer-token index was added: no
  collision was observed, and UUID collision risk does not justify a separate
  cleanup policy or deployment scan.

## Phase 5 — Frontend and accessibility

- [ ] **5.1 P2 — Fix concrete markup issues before a redesign.**
  Bootstrap 5 migration fixed the missing modal name, repeated RSVP field IDs,
  implicit Close-button type, and unnamed Trix controls. The Firefox suite proves
  Close does not save changes and covers modal focus/opening behavior. A focused
  accessibility-tool pass and narrow-screen check of the organizer's long secret
  link remain.

- [x] **5.2 P2 — Modernize incrementally, with the current UI as a baseline.**
  Completed with Propshaft, dartsass-rails, jsbundling-rails/esbuild, Turbo,
  Stimulus, Action Text/Trix, and Bootstrap 5.3.8. Browser dependencies are owned
  by one npm lockfile; jQuery and vendored JavaScript are removed. Firefox covers
  editor, uploads, navigation, clipboard, RSVP actions, Bootstrap modals, and
  Turbo snapshot cleanup. Original finding:
  Bootstrap 4, Sprockets/SassC, CoffeeScript, jQuery, UJS, and Turbolinks are real
  current dependencies. Plan a measured path toward the playbook's Bootstrap 5,
  modern Rails assets, and small Stimulus/Turbo enhancements. Do not simultaneously
  replace the editor, navigation, CSS, and backend behavior in one unobservable
  change. Move the inline `ClipboardJS` initialization out of the layout and
  manage listener teardown; report copy success/failure accessibly. Verify
  existing editor content compatibility and attachment URLs before migration.

- [ ] **5.3 P3 — Prefer existing formatting and layout primitives.**
  Event pages already use the named date format. Presenter `strftime` calls and
  repeated `Date.today` calls can use shared formats and Rails current-date
  helpers. Replace duplicate response-group rendering with a helper/partial only
  where privacy and organizer/public differences remain explicit. Retain the
  simple responsive layout; a large UI exploration catalog is unnecessary for
  these defect fixes.

## Phase 6 — Runtime and dependency maintenance

- [x] **6.1 P1 — Update patch levels, then plan supported runtime movement.**
  [Ruby 3.3.12](https://www.ruby-lang.org/en/news/2026/07/16/ruby-3-3-12-released/)
  is pinned in `.ruby-version`, `Gemfile.lock`, and CircleCI; the Ruby buildpack
  reads the same lockfile version for deploys. This is the latest Ruby 3.3
  security-maintenance release as of 2026-09-18 and includes security fixes in
  ERB and net-imap. Plan a move to a newer supported Ruby series before Ruby 3.3
  reaches end of life in March 2027. Process the remaining audit worklist in
  reviewable dependency groups; preserve the current product and verify native-gem
  and asset compatibility.

- [x] **6.2 P2 — Finish framework-default adoption consciously.**
  Rails 8.1 defaults are adopted incrementally from the original 5.2 baseline.
  The key-generator digest remains SHA-1 so existing RSVP session cookies and
  persisted Action Text attachment SGIDs stay valid. This compatibility hold is
  explicit and tested. Time-zone preservation is covered by behavior rather than
  the deprecated Rails setting.

- [x] **6.3 P2 — Make browser/runtime dependency ownership explicit.**
  Node 24 is aligned across `.node-version`, `package.json`, CircleCI and the Node
  buildpack. npm owns the browser graph, esbuild builds JavaScript, dartsass-rails
  builds Bootstrap and application SCSS, and Propshaft fingerprints both outputs.
  CI installs and audits the same lockfile before compiling. Unused Jbuilder,
  Octicons, and direct mail adapter dependencies have been removed.

## Phase 7 — CI and operations follow-up

- [x] **7.1 P1 — Make CI observe the important failure modes.** `bin/ci` is the
  shared local and CircleCI entry point. It gates on Bundler Audit, Brakeman,
  `zeitwerk:check`, npm audit, asset compilation, and the entire randomized RSpec
  suite, including headless Firefox. CircleCI stores JUnit results and browser
  failure screenshots, and deploys `main` only after that job passes. Formatting
  and style checks remain a separate, lower-priority cleanup so they do not obscure
  the failure modes this task was intended to cover.

- [ ] **7.2 P2 — Add a real health route and deployment verification.**
  Rails' lightweight `/up` route and a request regression are implemented. A
  Dokku `postdeploy` task now reports the exact `GIT_REV` to Honeybadger and
  propagates configuration/API failures instead of hiding missed deploy markers.
  The 2026-09-22 production log confirms a successful release migration, Puma
  startup, public cutover, and Honeybadger notification for the deployed main
  revision. It also showed that Dokku was relying only on port and uptime checks;
  `app.json` now requires `/up` to pass before traffic switches. Keep this item
  open until a production deploy log confirms that named HTTP check and the
  public read path remains healthy. Keep the real Dokku `Procfile`; no additional
  queue/deployment platform is needed.

- [ ] **7.3 P2 — Extend backup/recovery verification when operationally needed.**
  The new `db:pull_production` has strict local-target/confirmation guards,
  validated archives, backup retention, and fake-command recovery tests. Those
  are a useful foundation. `db:backup_production` now creates and downloads a
  timestamped archive, checks its catalog, and reads the complete archive without
  changing either database. This does not replace a real export/restore/recovery
  drill. PostgreSQL
  client/server compatibility, and concurrent local connection handling were
  not tested in this assessment. Run such checks only against deliberately
  disposable local databases and authorized production exports. Do not weaken
  the target guards to make a local rehearsal convenient.

- [ ] **7.4 P3 — Add a focused formatting and lint baseline.** Evaluate Omakase
  Ruby and proportionate ERB, JavaScript, and CSS checks against the modernized
  stack. Introduce them in reviewable groups, fix real findings, and avoid blanket
  suppression or a repository-wide mechanical rewrite.

## Verified healthy and accepted decisions

- **Scoped organizer access:** wrong organizer tokens return 404 without mutation;
  valid tokens for another event cannot update that event's unrelated RSVP.
- **Public RSVP scoping:** a cross-event DELETE returns 404 without deleting the
  response. Missing-session handling remains a separate defect, not proof of
  successful unauthorized deletion.
- **Dashboard authentication:** an unauthenticated request returns 401.
- **Rendering controls:** public hidden-name mode excludes another guest's name;
  sampled `<script>`/event-handler content is removed by the Rails sanitizer.
  This limited probe does not clear all old-editor or sanitizer advisories.
- **Conventional mutation verbs and strong parameters:** reviewed routes use
  POST/PATCH/PUT/DELETE; organizer updates permit explicit fields. No GET mutation
  was found in the controller review.
- **Intentional preloading:** dashboard event/response loading avoids N+1 queries.
  Its unbounded result size is addressed separately.
- **Runtime/asset baseline:** Rails eager loading and test-environment asset
  compilation pass; the sampled real-browser product flows work.
- **Test side effects:** test config uses disk storage and test mail delivery;
  Honeybadger reporting is disabled in test.
- **Source secrets:** `.env`, the credentials master key, temp backups, and the
  existing `db.dump` are not tracked by this checkout. This was a current-tree
  check, not a full Git-history secret scan.
- **Accepted product direction:** preserve accountless event creation and private
  organizer links. No new risk acceptance or permission to deploy/import is
  inferred from this assessment.

## Reassessment method

Record date/commit/dirty scope; run the actual suite and scans; inspect routes,
schema, config, and code; reproduce suspected defects with local synthetic data;
measure both queries and loaded rows; verify browser-dependent changes in a real
browser; consult dated upstream sources for maintenance/security claims. Keep
verified defects, recommendations, accepted decisions, and untested hypotheses
separate. Update completed checkboxes with their validation evidence and retain
this dated baseline when subsequent changes invalidate the original findings.
