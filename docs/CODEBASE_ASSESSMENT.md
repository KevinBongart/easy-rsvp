# Easy RSVP — Codebase Assessment and Remediation Plan

Assessed **2026-09-08**, branch `main`, commit `38413a5`, including the existing
uncommitted playbook/agent documentation, README/environment additions, and
production-database pull implementation/specs from the preceding task.

Status: **assessment complete; test-harness follow-up implemented; product remediation remains pending**. This replaces the
initial assessment brief. Standards: [Rails Engineering Playbook](RAILS_ENGINEERING_PLAYBOOK.md).
Application reference: [AGENTS.md](../AGENTS.md).

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

Phase 0.1 and 0.3 now have substantial coverage, but remain open for the unresolved
unpublished-write/monthly-statistics policies, production mail-host configuration,
and fuller failure-path coverage. Phase 7.1 has local/hosted test parity and browser
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

- [ ] **0.1 P1 — Cover access boundaries and malformed requests.** Add request
  specs for wrong organizer tokens, cross-event RSVP update/delete, dashboard
  authentication, empty/missing session state, unsupported/missing submit values,
  and unpublished-event writes. Evidence: only
  [event features](../spec/features/event_spec.rb) and
  [dashboard feature](../spec/features/admin_dashboard_spec.rb) exist for the
  product; neither exercises these negative paths. Keep no-mutation assertions.

- [x] **0.2 P1 — Add a small real-browser suite.** Implemented in the follow-up above. Original finding: Keep Rack Test for fast forms;
  add Selenium/headless Firefox for editor save/upload, clipboard, RSVP-again,
  organizer response modals, and UJS deletion. Reproduce upload-handler duplication
  across repeated navigation before fixing it. `spec/rails_helper.rb` currently
  has no JS driver and the Gemfile does not include Selenium. A local one-off
  browser pass cannot replace CI coverage.

- [ ] **0.3 P2 — Cover model, presenter, and mail contracts.** Add tests for event
  deletion with/without responses, response inclusion, monthly/yearly date
  semantics, hidden-name rendering, configured mail URLs, blank/invalid uploads,
  and failed mail delivery. Include different event dates and creation dates so
  the dashboard test cannot accidentally conflate them.

- [x] **0.4 P2 — Make the harness deterministic and self-contained.** Implemented in the follow-up above. Original finding: Freeze
  date-dependent dashboard examples, use explicit synthetic Basic Auth settings,
  enable randomized order (currently inside the commented block in
  `spec/spec_helper.rb`), and retain test disk storage and mail delivery. Add a
  documented local CI command as tooling lands in Phase 7.

## Phase 1 — Correctness and proven bit-rot

- [ ] **1.1 P1 — Repair event deletion.** `Event` has `has_many :rsvps` without a
  dependent policy (`app/models/event.rb:4`), while `rsvps.event_id` has a foreign
  key (`db/schema.rb:73`). `EventsAdminController#destroy` at line 19 calls
  `@event.destroy`. A token-authorized DELETE of an event with one RSVP raises
  `ActiveRecord::InvalidForeignKey`; an empty-event path alone misses the defect.
  Define the intended cascade, implement it transactionally, and test both cases
  and unauthorized deletion. This route exists even though no event-delete
  control is currently rendered.

- [ ] **1.2 P1 — Handle malformed RSVP submissions and absent session ownership.**
  `app/controllers/rsvps_controller.rb:5` calls `downcase` on `params[:commit]`
  without validating its presence/type. Missing `commit` raises `NoMethodError`.
  Lines 23–25 pass a missing session entry into `in?`, raising `ArgumentError`
  on a sessionless DELETE of an existing RSVP. Reject malformed input with a
  controlled response; treat a missing ownership list as empty and preserve the
  response. Test nil, wrong-shaped values, unsupported answers, and denied deletes.

- [ ] **1.3 P2 — Persist session cleanup after RSVP deletion.** Line 27 reassigns
  `event_session -= [@rsvp.hashid]` but never writes it back to `session`.
  The record disappears while the cookie's ownership array retains its hashid.
  Repeated use grows stale session data. Store the reduced array or delete an
  empty key; test both database state and subsequent session contents.

- [ ] **1.4 P1 — Validate response membership.** `app/models/rsvp.rb:13` only
  validates response presence. The organizer endpoint permits `response`
  (`app/controllers/admin/rsvps_controller.rb:26`). A PATCH with `unexpected`
  persists successfully; the public view only groups yes/maybe/no and omits
  that guest (`app/views/events/show.html.erb:40`). Add inclusion validation,
  a safe data cleanup/migration, and a database check constraint; test model,
  request, and direct-database writes. Do not silently coerce existing bad data.

- [ ] **1.5 P2 — Decide and enforce unpublished-event write semantics.** Public
  display checks `published?` (`app/controllers/events_controller.rb:34`), but
  `RsvpsController#set_event` does not. A direct POST adds an RSVP to an unpublished
  event. This is a verified behavior gap; the UI promises hidden visibility,
  not explicitly frozen responses. Decide whether unpublishing also closes
  responses, then document and test the chosen create/delete policy. Do not
  infer that organizer editing should stop.

- [ ] **1.6 P1 — Fix production email link hosts.**
  `config/environments/production.rb:60` hardcodes `example.com`, overriding
  `config/application.rb`'s `DOMAIN`. A local production boot confirmed this
  even with a nonempty synthetic `DOMAIN`. `UserMailer` renders both organizer
  and guest URLs using that host. Configure the intended HTTPS host and add a
  configuration/message-body regression test. The email endpoint remains live,
  although the current organizer page has no email form and the feature test's
  email journey is commented out; decide whether to restore that feature or
  remove the unused endpoint in a separate product decision.

- [ ] **1.7 P1 — Register one attachment handler per document lifecycle.**
  `app/assets/javascripts/trix_attachments.js:37` adds a document listener inside
  every `turbolinks:load`. In Firefox, three additional load events followed by
  one synthetic attachment event triggered **four upload sends**, intercepted
  before network/storage access. Register once or clean up explicitly; test
  repeated real navigation and one upload request. Scope `xhr` locally (line 15
  currently assigns a global), handle network/non-2xx/invalid-JSON failures, and
  give users a recoverable error instead of a stuck attachment.

- [ ] **1.8 P3 — Remove verified dead scaffolding and unused dependencies.**
  `Rsvp#session_key` has no caller; helpers are empty; `events.scss` contains
  only generated comments. Jbuilder has no templates/call sites, and octicons/
  octicons_helper have no application usage (the logo is an image). Remove with
  a boot/assets/full-suite check. `config/puma.rb:37` has a conditional Solid Queue
  plugin despite no Solid Queue gem or worker; remove that misleading branch.
  `ApplicationJob` has no subclasses; retain it only with an explicit future use.
  Do not remove CoffeeScript, clipboard, Trix, or mailer code as "unused": they
  have live consumers or routes.

## Phase 2 — Security and privacy

- [ ] **2.1 P1 — Patch relevant dependency exposures and add audit coverage.**
  Use the [deduplicated audit](assessment/2026-09-08-dependency-audit.md) as the
  worklist, prioritizing request parsing, HTML sanitization, Active Storage, and
  the web server before development-only tooling. Rails 8.0.2.1 predates the
  [March security patches](https://rubyonrails.org/2026/3/23/Rails-Versions-7-2-3-1-8-0-4-1-and-8-1-2-1-have-been-released)
  and [July variant-processing patch](https://rubyonrails.org/2026/7/29/Rails-Versions-7-2-3-2-8-0-5-1-and-8-1-3-1-have-been-released).
  Rails 8.0.5.1 is a verified patched release on the current minor line; choose
  the current compatible release at implementation time. Rack 3.2.1 matches
  [multipart memory-exhaustion advisories](https://github.com/rack/rack/security/advisories/GHSA-p543-xpfm-54cp),
  relevant to this app's public multipart endpoint. No large-payload attack was
  run. Check proxy limits before making deployment-level exploitability claims.
  Do not call every installed gem an exposed production feature: Action Cable,
  Action Text, IMAP clients, and development tooling have different reachability.

- [ ] **2.2 P1 — Replace/update the unaudited vendored editor.**
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

- [ ] **2.3 P1 — Keep organizer credentials out of URL logs.**
  Routes embed the credential in the path (`config/routes.rb:4`), and Rails'
  request-start log includes that path verbatim. A local logger probe found the
  synthetic token even though parameter filtering includes `:token`. Redact these
  path segments in application, proxy, and error-monitoring logs, or plan a
  credential exchange/session design while preserving shareable organizer links.
  Prove redaction with synthetic tokens and review logging configurations. Merely
  adding another filtered parameter does not fix raw path logging.

- [ ] **2.4 P1 — Bound and own public uploads.**
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

- [ ] **3.1 P2 — Close onboarding and feature-documentation gaps.** Keep README
  and AGENTS current after each fix. Explain event/RSVP deletion rules,
  unpublishing semantics, dashboard date semantics, and the email feature's
  availability. Document required versus optional environment settings,
  canonical host, local file-storage setup, and the local checks command once
  introduced. The preceding documentation/import task is completed preparation,
  not evidence that the old product flows have been repaired.

- [ ] **3.2 P1 — Isolate development storage and email.**
  `config/environments/development.rb:32` selects `:amazon`; production also uses
  that service, whose bucket is fixed in `config/storage.yml`. SMTP delivery is
  enabled in `config/application.rb`. The README now warns about these existing
  effects, but ordinary development should default to disk/local email capture.
  Imported blobs retain a `service_name`, so changing only the default service
  does not guarantee isolation of restored records. Specify a safe local-copy
  policy and verify it without writing to real S3 or SMTP.

## Phase 4 — Architecture, duplication, and data integrity

- [ ] **4.1 P2 — Bound dashboard work in SQL.**
  `app/controllers/admin/events_controller.rb:4` uses
  `Event.all.includes(:rsvps).order(...).to_a`; line 8 paginates afterward, at
  1,000 rows per page. Preserve the two-query behavior where useful while using
  database pagination, aggregate response counts, and count-based sorting.
  Add a scale test that limits instantiated rows as well as query count; a
  constant query count alone would let the present problem pass.

- [ ] **4.2 P2 — Define one meaning for dashboard counts.**
  `Admin::EventStats#yearly_counts` groups by `created_at.year` (line 29), but
  `count_events_in_month` uses the event's scheduled `date` (line 78).
  A January-created, September-scheduled event counts as a September event.
  The "so far" extrapolation then scales the entire scheduled-month count by
  elapsed days, including future events. Decide whether these are creation
  metrics or event-calendar metrics, label them accordingly, and test dates that
  differ. Keep numeric counts numeric until formatting; avoid parsing formatted
  strings back into numbers. Cache or aggregate repeated monthly calculations
  within one presenter instance rather than scanning repeatedly.

- [ ] **4.3 P2 — Consolidate parsing without merging authorization contexts.**
  Identical `hashid_from_param` methods exist in EventsController,
  EventsAdminController, RsvpsController, and Admin::BaseController. Give public
  ID parsing one owner and preserve organizer token matching at the boundary.
  Clarify `Admin::AdminController` versus `Admin::BaseController` naming only
  behind the negative request tests; one is Basic Auth, the other token auth.
  Keep these small controllers small rather than extracting one-line services.

- [ ] **4.4 P2 — Tighten persisted invariants deliberately.**
  `rsvps.name`, `response`, and `event_id` are nullable in the schema; `published`
  is also nullable. Model-only presence checks do not protect direct/concurrent
  writes. Inventory existing invalid data through an authorized path, document
  cleanup choices, then add appropriate null/check constraints. Assess whether a
  unique organizer token constraint is useful, without overstating collision risk
  for UUID-generated tokens. Preserve the existing foreign key and valid data.

## Phase 5 — Frontend and accessibility

- [ ] **5.1 P2 — Fix concrete markup issues before a redesign.**
  `app/views/events_admin/show.html.erb:90` gives every modal an
  `aria-labelledby="emailModalLabel"` reference, but no such label exists;
  repeated RSVP fields reuse IDs. The Close button at line 107 has no explicit
  `type="button"`. In the observed Firefox/Bootstrap interaction Close did
  **not** persist a changed name, so this is markup hardening rather than a
  reproduced unintended-save bug. Editor labels target a hidden field, while
  `<trix-editor>` has no explicit accessible name; verify with accessibility
  tooling and name the actual control. Add keyboard/focus and narrow-screen
  checks to the browser suite, including the organizer's long secret-link text.

- [ ] **5.2 P2 — Modernize incrementally, with the current UI as a baseline.**
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

- [ ] **6.1 P1 — Update patch levels, then plan supported runtime movement.**
  Ruby is pinned to 3.3.4 in both `.ruby-version` and CircleCI. Ruby 3.3 is now in
  [security maintenance](https://www.ruby-lang.org/en/downloads/branches/), and
  [3.3.11](https://www.ruby-lang.org/en/news/2026/03/26/ruby-3-3-11-released/)
  already contained a security-related bundled-gem update. Choose the current
  compatible patched runtime and align local/CI/deploy versions. Do not assume
  updating the Rails gem updates Ruby's bundled libraries or vendored JS.
  Process the audit worklist in reviewable dependency groups; preserve the
  current product and verify native-gem/asset compatibility.

- [ ] **6.2 P2 — Finish framework-default adoption consciously.**
  `config/application.rb:25` still loads Rails 5.2 defaults. The 7.0, 7.2, and
  8.0 defaults files contain only commented proposals. Choose and test defaults
  incrementally, especially cookies/serialization, redirects, time handling,
  and assets. Resolve the observed Rails 8.1 timezone-preservation deprecation
  with a behavior test. Do not just delete the files and switch defaults blindly.

- [ ] **6.3 P2 — Make browser/runtime dependency ownership explicit.**
  `.node-version` pins 14.15.4 while `package.json` has no dependencies; JavaScript
  is served from gems/vendor and Node may still be an ExecJS runtime for assets.
  Decide its build role, update or remove the pin accordingly, and cover that
  path in CI. Keep required mail adapter gems until their dependency/runtime
  purpose is verified; absence of an application-level `Net::SMTP` call alone
  does not prove the mail stack can remove them.

## Phase 7 — CI and operations follow-up

- [ ] **7.1 P1 — Make CI observe the important failure modes.** CircleCI currently
  installs gems, creates/loads the test DB, and runs RSpec before deploying
  successful `main` builds. Add pinned Brakeman/bundler-audit, asset compilation,
  focused Firefox specs, and `zeitwerk:check`. Introduce Omakase Ruby style and
  appropriate ERB/JS/CSS checks as separate cleanup work, not blanket suppressions.
  Provide one local command matching hosted CI and retain browser-failure evidence.
  Security scans should become real gates rather than occasional local tools.

- [ ] **7.2 P2 — Add a real health route and deployment verification.**
  Production config silences `/up`, but a local request returns 404 because it
  is treated as an event ID. Add a lightweight explicit route and verify boot,
  release migrations, health, and one read path after authorized deployment.
  Keep the real Dokku `Procfile`; no additional queue/deployment platform is needed.

- [ ] **7.3 P2 — Extend backup/recovery verification when operationally needed.**
  The new `db:pull_production` has strict local-target/confirmation guards,
  validated archives, backup retention, and fake-command recovery tests. Those
  are a useful foundation. A real export/restore/recovery drill, PostgreSQL
  client/server compatibility, and concurrent local connection handling were
  not tested in this assessment. Run such checks only against deliberately
  disposable local databases and authorized production exports. Do not weaken
  the target guards to make a local rehearsal convenient.

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
  Rollbar is explicitly disabled in test.
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
