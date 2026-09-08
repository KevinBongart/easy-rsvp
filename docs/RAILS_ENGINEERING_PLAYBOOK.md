# Rails Engineering Playbook

Status: cross-repository default

Last reviewed: 2026-08-21

## Purpose

This document describes the default engineering standards for Ruby on Rails
applications maintained by Kevin Bongart and by coding agents working on his
behalf. It is intentionally generic: each application still needs its own README,
current architecture reference, business rules, operational notes, and feature
plans.

These are strong defaults, not cargo-cult requirements. An application-specific
document may override them when the product or operating environment genuinely
requires something else. The override should state the reason and the tradeoff so
future maintainers do not repeatedly rediscover the decision.

The central goal is a small, modern, unsurprising Rails application that remains
easy to understand, test, operate, and safely change—by a person or by an agent.

## Guiding principles

1. **Build the smallest useful product increment.** Prefer a narrow vertical
   slice that users can benefit from over a broad architectural project.
2. **Let Rails be Rails.** Use framework conventions, helpers, generators, and
   standard libraries before inventing application infrastructure.
3. **Keep the system boring.** Familiar components, explicit data flow, and
   conventional file placement are features.
4. **Server-render by default.** HTML, Turbo, CSS, and browser primitives cover
   most product needs. JavaScript is a progressive enhancement, not the starting
   point.
5. **Put domain behavior in named domain objects.** Controllers coordinate HTTP;
   services coordinate workflows; models protect persisted invariants.
6. **Test behavior at the cheapest useful level.** Maintain many fast tests and a
   small number of real-browser tests for the integration seams that unit tests
   cannot cover.
7. **Measure before optimizing.** Protect query counts and important runtime
   characteristics with regression tests. Add caching only after measurement.
8. **Prefer maintained libraries to bespoke infrastructure.** Still avoid adding
   a dependency when Rails or a few obvious lines of code already solve the
   problem well.
9. **Delete drift and dead weight.** Unused code, dependencies, generated config,
   and stale documentation increase the cost and risk of every future change.
10. **Documentation is part of correctness.** An inaccurate agent reference can
    be more dangerous than no reference at all.
11. **Production safety is a separate permission boundary.** Local repository
    access never implies permission to access a server, production database,
    external account, or billable API.
12. **Make failure graceful and recoverable.** Writes should be transactional and
    idempotent where retries are plausible; background pipelines should be
    observable and resumable when the cost justifies it.

## Preferred application baseline

For a new conventional web application, start with the current stable releases
that the deployment environment supports:

| Concern | Default |
| --- | --- |
| Language | Current stable Ruby, pinned in `.ruby-version` |
| Framework | Current stable Rails with current security patches |
| Web server | Puma |
| Database | PostgreSQL |
| Authentication | Devise when accounts are required |
| UI | Server-rendered ERB and Bootstrap 5 |
| JavaScript | Importmap, Turbo, and small Stimulus controllers |
| Assets | Propshaft and Dart Sass when Sass is needed |
| Tests | RSpec and FactoryBot for new apps; preserve a healthy established Minitest suite |
| Browser tests | Capybara/Selenium with headless Firefox |
| Code style | `rubocop-rails-omakase`, unmodified and with no project-specific cop configuration |
| CI | GitHub Actions or CircleCI, mirrored by one local command |
| Deployment | Dokku with a `Procfile` unless the app documents another platform |
| Jobs | Active Job with Sidekiq only when asynchronous work is real |
| Queue/cache store | Redis only when required by jobs, caching, or another measured need |

Do not add Redis, Sidekiq, Action Cable, a JavaScript bundler, a frontend framework,
Kamal, or a multi-database layout merely because Rails generated a template for
it. Every running component and every checked-in config file must have an owner
and a current use.

Existing applications should be modernized incrementally. A framework upgrade is
not permission to rewrite working product behavior or replace familiar libraries
without a measured benefit.

Use Rails Omakase as the Ruby style, not as the starting point for a bespoke
house style. Apart from the inheritance stub RuboCop needs to load
`rubocop-rails-omakase`, do not add project-specific cop settings, generated
`.rubocop_todo.yml` exclusions, or gradual-rollout overrides by default. Fix the
code instead. A rare exception must document the concrete incompatibility and
should be removed when that incompatibility ends.

## Rails and Ruby conventions

### Prefer framework vocabulary

- Use RESTful resources and conventional controller actions.
- Inherit Active Record models from `ApplicationRecord`.
- Use associations to express ownership and scope queries through those
  associations.
- Use validations for user-facing feedback and database constraints for actual
  integrity.
- Use scopes for repeated query concepts, not for one-off fragments.
- Use strong parameters and the correct HTTP verbs. GET must never mutate state.
- Use ActiveSupport time helpers such as `Date.current`, `Time.current`,
  `2.days.ago`, and `beginning_of_week` instead of reimplementing them.
- Define named `to_fs` date/time formats rather than scattering `strftime` calls.
- Use Rails formatting and tag helpers rather than manually constructing strings
  or HTML.
- Prefer Rails form builders for ordinary forms. Add a form-builder gem only when
  it materially simplifies the product; keep one current initializer rather than
  layers of generated configuration overriding each other.
- Prefer Turbo Frames, Turbo Streams, form helpers, signed IDs, Active Job,
  Action Text, and other Rails facilities when they match the requirement.

### Write modern, readable Ruby

- Prefer keyword arguments for non-obvious inputs.
- Keep public interfaces small and split complex work into well-named private
  methods or collaborators.
- Prefer clear collection operations and early returns to deep nesting.
- Use immutable value objects for domain values that need equality or are used as
  hash keys. Their `==`, `eql?`, and `hash` contracts must agree.
- Use `Data` or a small explicit class for typed result objects when a raw hash
  would make contracts ambiguous.
- Name domain concepts, not mechanisms: `MemberAvailability` is better than
  `EventProcessor`; `MealPlacement` is better than `RecordMover`.
- Replace magic strings and numbers that carry domain meaning with named
  constants. Names should describe the concept, not its storage representation.
- Avoid clever metaprogramming, speculative DSLs, and inheritance hierarchies
  that save a few lines while hiding control flow.
- Default to self-explanatory code rather than comments. Add comments for
  surprising business rules, protocol quirks, concurrency constraints, or lines
  that would otherwise look incorrect.

### Treat duplication as a design signal

Duplication in business rules is especially dangerous because copies silently
diverge. Extract a shared owner when the same decision appears in multiple
controllers, views, services, or jobs.

Use the right extraction:

- model or value object for a domain invariant;
- service for a multi-step workflow;
- presenter or helper for shared presentation logic;
- partial for repeated markup;
- scope or query object for repeated query semantics;
- constant or lookup table for repeated domain values;
- concern only for genuinely shared behavior with a coherent public contract.

Do not abstract merely because two incidental code fragments look similar.
Prefer a small amount of obvious duplication over a generic abstraction that
erases the domain language. High-risk duplicated rules—payments, permissions,
normalization, retries, state transitions—should be centralized earlier than
cosmetic duplication.

Never override an inherited method with an identical copy. Rely on inheritance
or change the shared owner explicitly.

## Application architecture

### Controllers

Controllers own HTTP concerns:

- authentication and authorization entry points;
- parameter parsing and strong parameters;
- finding records through the correct tenant or owner;
- invoking a model, service, form object, or query object;
- selecting redirects, status codes, flashes, and rendered templates.

They should not own external API normalization, payment rules, scoring
algorithms, multi-record transactions, long calculations, or large presentation
transformations.

For complex pages with multiple failure paths, initialize every view-facing value
to a safe default before loading external data. Error handling should preserve a
renderable page rather than rescue one exception only to crash in the template on
an unset instance variable.

### Models

Active Record models own persisted relationships and invariants. They may contain
small, cohesive domain behavior closely tied to their state.

Use callbacks sparingly:

- callbacks are suitable for local invariants and unavoidable lifecycle cleanup;
- callbacks should not hide external network calls, expensive workflows, or
  surprising cross-model orchestration;
- after-commit work must be intentional and tested, particularly when it can be
  billable or slow.

Mirror important uniqueness and state rules in the database. A model validation
alone does not protect against concurrent writes.

### Services and form/workflow objects

Use services for meaningful business operations, external integrations, and
multi-step workflows. A service should have one clear responsibility, a small
public API—often `.call` or one domain verb—and an explicit result or failure
contract.

Good service candidates include:

- payment or invitation acceptance;
- recommendation, scoring, and analysis pipelines;
- API clients and response normalization;
- multi-record creation or placement under a transaction;
- import/export and serialization;
- idempotent form workflows that resolve or create related records;
- asynchronous pipeline stages.

Do not create a service that merely wraps one Active Record call without adding a
domain boundary. Do not turn `app/services` into a miscellaneous directory.

API-shape normalization belongs in a service or serializer, not in controllers or
presenters. Presenters should receive application-shaped data rather than learn
every upstream provider's response format.

### Presenters, helpers, and serializers

- Presenters prepare view-specific data and formatting when a view would
  otherwise contain branching or repeated calculations.
- Helpers own small reusable rendering decisions and must use Rails' escaping and
  tag builders.
- Partials own repeated markup.
- Serializers own an export or API response shape.
- Views should remain declarative and should not issue queries.

Keep domain decisions out of CSS-class lookups and ERB conditionals when the same
decision is used elsewhere.

### Background jobs

Introduce Sidekiq and Redis when work is slow, retryable, scheduled, parallel, or
should not block an HTTP request. Do not introduce them in anticipation of a
possible future need.

Jobs should:

- be idempotent or safely detect completed work;
- accept stable identifiers rather than serialized model instances;
- delegate domain work to services;
- use bounded retries with appropriate backoff;
- log enough context to diagnose failures without exposing secrets;
- make partial progress visible when a pipeline is expensive;
- support safe resume or replay when repeating completed stages would be costly;
- avoid unbounded fan-out and respect database connection-pool limits.

Schedule recurring work through one documented mechanism. Do not leave multiple
competing cron, Sidekiq scheduler, and platform scheduler configurations in the
same application.

### External APIs

- Put provider access behind a client or service boundary.
- Configure explicit timeouts and bounded retries where appropriate.
- Stub network traffic by default in the test suite.
- Give the small number of real integration checks an explicit opt-in.
- Never let seeds or ordinary model factories make billable API calls.
- Keep raw provider shapes out of controllers and views.
- Treat rate limits, partial responses, truncation, malformed JSON, and stale
  credentials as expected failure modes.
- Treat AI output as untrusted provider data: validate its shape, constrain values
  with application allowlists where possible, detect truncated responses, and
  retain enough observability to inspect failed stages without logging secrets.
- Record whether a command performs reads, writes, or billable operations.
- Use read-only `rails runner` verification against real data only when access is
  already authorized. Never infer permission to write or to bypass an environment
  guard.

## Database design, tenancy, and performance

### Integrity first

- Add foreign keys, null constraints, check constraints, and unique constraints
  for real invariants.
- Backfill data before making a new column non-null.
- Resolve existing duplicates explicitly before adding uniqueness.
- Keep migrations reversible when a truthful rollback exists; raise an explicit
  irreversible migration when rollback would lose or misinterpret data.
- Consider table locks and deployment duration for migrations on live tables.
- Test important constraints by bypassing model validations.
- Make retryable submissions idempotent with a token or natural key rather than
  guessing whether two similar records were intentional.

### Tenant and ownership boundaries

Every tenant-facing lookup begins from the authenticated owner or tenant
association, for example `current_household.recipes.find(params[:id])`. Global
class-level lookups are reserved for clearly authorized cross-tenant admin code.

Add negative request tests proving that one tenant cannot read, update, or delete
another tenant's records. Authorization is incomplete until the forbidden case is
tested.

### Query discipline

- Preload associations intentionally with `includes` or `preload`.
- Do not let views or presenters trigger hidden per-record queries.
- Bulk-load history or aggregate data once and pass an explicit data object to
  consumers.
- Prefer database filtering and aggregation when it is clearer and avoids loading
  large collections.
- Use a query counter around query-sensitive endpoints and services.
- Compare small and large representative datasets: the count should stay constant
  when the result volume grows.
- Preserve an already optimized query count during refactoring.
- Add caching only after measurement identifies a useful, stable cache boundary;
  document invalidation and test it.

## Frontend and interaction design

### HTML and CSS first

Start with semantic server-rendered HTML and a usable non-JavaScript flow.
Bootstrap 5 is the default design system. Use its grid, responsive containers,
spacing, forms, utilities, and accessible components before adding custom layout
CSS.

Customize Bootstrap through design tokens and Sass variables rather than copying
framework rules or scattering hex values. Keep the Bootstrap CSS and JavaScript
versions aligned. Avoid unpinned CDN dependencies; local gem/importmap assets are
preferred when practical.

Use the current asset pipeline. Do not combine Propshaft with an obsolete
Sprockets/LibSass stack unless the migration state is explicit and temporary.
Do not introduce CoffeeScript, Turbolinks, jQuery-dependent UI, LibSass, Uglifier,
or indiscriminate `require_tree` loading in new code.

### JavaScript is a last-mile enhancement

Before writing JavaScript, ask whether the behavior can be handled by:

1. a normal link or form;
2. CSS;
3. Turbo navigation, Frames, or Streams;
4. a native browser capability;
5. a small Stimulus controller.

Introduce a bundler or frontend framework only when a demonstrated requirement
cannot be served cleanly by the Rails-native stack.

Stimulus controllers should be small, single-purpose, and declaratively connected
through targets, values, and actions. They must clean up timers, event listeners,
observers, and temporary DOM in `disconnect`. Keep server responses authoritative
for persisted state.

Do not hand-roll `fetch` and DOM replacement when a Turbo Frame is the natural
solution. Do not make pointer-only interactions the sole path for essential
actions.

### Accessibility and responsive behavior

- Use semantic controls with accurate accessible names.
- Preserve keyboard access and visible focus.
- Provide live-region announcements for important asynchronous results.
- Respect reduced-motion preferences.
- Test touch-sized targets and narrow layouts when the product is used on phones.
- Keep decorative motion out of document flow so it cannot shift the page.
- Verify that table, overflow, and transformed elements do not clip drag or
  animation feedback.

### Development-only UI labs

When a feature introduces an unsettled visual or interaction decision, build a
local-only development page that shows many replayable variants using realistic
content.

The lab should:

- split independent decisions into independent sections;
- usually show at least ten meaningful options for each uncertain component;
- vary the actual dimensions under review—density, contrast, motion, placement,
  capacity, and feedback—not merely labels;
- include two-, three-, empty-, dense-, error-, and long-content states as
  applicable;
- allow animations and interactions to be replayed;
- mark the current implementation as provisional;
- reuse the application's typography and design tokens;
- remain inaccessible in production;
- have a request test proving the page and compiled stylesheet load.

The purpose is to make product judgment cheap before production code hardens
around the first plausible idea. Once a choice is made, implement only the chosen
production behavior; the catalog may remain as a design record if it stays
maintained.

Always inspect the real feature page after choosing a variant. A good isolated
component can still make the surrounding calendar, table, or form unusably dense.

## Testing strategy

### Goals

The suite should be broad, deterministic, and fast enough to run constantly.
Optimize for confidence per second, not a coverage percentage or a raw example
count.

Use the test framework already established by the repository. RSpec and Minitest
are both acceptable; consistency inside an app matters more than cross-repo
uniformity.

### Test-driven development

Use Red–Green–Refactor for behavior changes:

1. **Red:** add or change the smallest test that specifies the desired public
   behavior and confirm it fails for the expected reason.
2. **Green:** implement the minimum coherent behavior that makes it pass.
3. **Refactor:** remove duplication, improve names and boundaries, and keep the
   suite green.

For a regression, reproduce the bug in a test before fixing it. Include the
negative or near-miss case when that is where the bug hides—for example, a word
boundary match should prove both `away` and `Castaway` behavior.

Test public behavior. Do not call private controller methods with `send` or assert
against internal instance variables when the behavior can be observed through a
request, result object, rendered page, or database state.

### Test layers

- **Model tests:** validations, associations, constraints, scopes, and compact
  stateful domain behavior.
- **Value-object tests:** equality, immutability, boundary calculations, and
  surprising domain rules.
- **Service tests:** workflow branches, result contracts, retries, normalization,
  transaction rollback, and external failures.
- **Request/controller tests:** routing, authentication, authorization, tenant
  isolation, parameters, status codes, redirects, and error rendering. Render
  views when controller tests are used so missing view state cannot hide.
- **Presenter/helper tests:** display decisions and formatting branches.
- **System/feature tests:** every important user-facing form flow and a small set
  of full journeys.
- **JavaScript unit tests:** isolated Stimulus timing, event, and cleanup behavior
  when the app contains meaningful JavaScript.

### Fast default, real browser where it matters

Use Rack Test for ordinary server-rendered system specs. Tag only genuinely
JavaScript-dependent examples for Selenium with headless Firefox.

Keep a small Firefox smoke suite that exercises the real asset/importmap/browser
integration, such as:

- a Turbo Frame update;
- Stimulus registration and keyboard behavior;
- one representative drag or rich-editor flow;
- locally loaded Bootstrap behavior.

JavaScript unit tests cannot catch a broken importmap pin, missing compiled asset,
or controller that never registers in the browser. Conversely, running every form
spec in Selenium makes the suite slower and more fragile without adding value.

### Suite hygiene

- Use transactional tests where possible.
- Build test data with factories or fixtures; do not reload full seeds before
  every example.
- A factory must create a realistic valid object without relying on pre-existing
  seed rows.
- Run examples in random order and make time travel block-scoped or reliably
  reset.
- Prevent real emails, payments, AI calls, and HTTP requests by default.
- Keep auth bypasses narrow and add explicit tests with real authentication.
- Test malformed input, empty state, provider failure, and rollback—not only the
  happy path.
- For concurrent or replayable writes, test both sequential replay and the
  database race path.
- Preserve screenshots from failed browser tests in CI.

### Verification beyond automated tests

For changes that depend on real provider data, run an authorized, read-only
integration check through the same service path the application uses. For visual
changes, boot the app, inspect the actual page at representative desktop and
mobile sizes, and check logs for errors and query growth.

Automated tests and a real-data or visual smoke check catch different classes of
failure. Use both in proportion to risk.

## Security and privacy baseline

Security work should be proportionate to the application, but the baseline is not
optional:

- authenticate and authorize access at the server;
- scope tenant records through ownership associations;
- use CSRF-protected non-GET verbs for mutations;
- escape output and use Rails tag helpers rather than `raw` string assembly;
- use strong parameters;
- filter passwords, tokens, payment fields, and private URLs from logs;
- keep secrets in Rails credentials or environment variables, never the repo;
- require the production master key when credentials are required;
- use modern payment APIs and never store raw card details;
- run Brakeman and dependency audits in CI;
- add rate limiting where authentication, payment, or public write abuse warrants
  it;
- configure CSP when external scripts or the application's risk profile make it
  valuable.

Record explicit owner decisions when a finding is accepted. Future assessments
should respect a documented acceptance instead of repeatedly reopening it unless
the threat model changes.

## Dependencies and generated infrastructure

### Choosing a dependency

Before adding a gem or package, ask:

1. Does Rails, Ruby, Bootstrap, or the browser already solve this?
2. Is the custom implementation security-sensitive, protocol-heavy, or likely to
   accumulate edge cases?
3. Is the library maintained, documented, compatible with the current Rails/Ruby
   version, and widely used?
4. Does its API reduce application code and cognitive load enough to justify its
   transitive dependencies and upgrade surface?
5. Can it be tested behind an application-owned boundary?

Prefer mature libraries for authentication, payments, queueing, feed/calendar
formats, pagination, HTTP protocols, and other edge-case-heavy domains. Prefer
small application code for simple product-specific transformations.

### Maintenance

- Keep Ruby, Rails patch releases, browsers, and security-sensitive dependencies
  current.
- Use Dependabot or equivalent coverage for Bundler, npm, and CI actions.
- Process dependency pull requests one at a time when they affect the same lock
  file.
- Resolve conflicts against current `main`, confirm the update is still needed,
  and close it if a newer version already shipped.
- Run the complete local suite before merge.
- Deploy and verify one dependency update before moving to the next when the
  requested workflow calls for serial production rollout.
- Stop on a substantive merge or deployment problem; do not stack uncertainty.
- Keep gem and browser-side package versions aligned when the same framework is
  represented in both ecosystems.
- Remove unused gems, packages, binstubs, initializers, and template config after
  verifying call sites.

Do not preserve a dependency only because removing it feels risky. Prove whether
it is used.

## Continuous integration

Provide one local command—preferably `bin/ci`—that mirrors hosted CI. It should
fail fast and normally include:

1. security scans (`brakeman`, Bundler audit, importmap/npm audit as applicable);
2. asset compilation;
3. Ruby linting;
4. ERB linting;
5. JavaScript and CSS linting when those assets exist;
6. the full Ruby test suite;
7. JavaScript unit tests when present.

Hosted CI should run for pull requests and pushes to `main`, use the pinned Ruby
and Node versions, start PostgreSQL and Redis only when needed, and install
Firefox/geckodriver for real-browser specs. Keep the workflow understandable;
split scan, lint, and test jobs when parallel feedback is useful.

CI is not a substitute for local verification. Conversely, a local green suite
does not turn an unexplained hosted failure into success. Distinguish code
failures from runner/infrastructure failures with evidence.

## Deployment and operations

Dokku is the normal deployment target. A conventional `Procfile` is preferred:

```text
release: bundle exec rails db:migrate
web: bundle exec puma -C config/puma.rb
worker: bundle exec sidekiq
```

Omit the worker when there are no background jobs. Document the actual process
types, backing PostgreSQL/Redis services, required environment variables, and
first-deploy steps.

Every deployed app should expose a lightweight health endpoint and have a
post-deploy verification appropriate to its risk:

- deploy completed and release migration succeeded;
- web process booted;
- health endpoint responds;
- workers and schedules are running when applicable;
- one key read path works;
- logs contain no boot loop, migration, or asset error.

Do not check in an unedited Kamal file, Docker setup, queue config, or platform
template when Dokku is the real deployment system. Competing deployment stories
create false instructions for both people and agents.

Production deploys, SSH, database copies, data tasks, external writes, and billable
API operations require explicit authorization. A request to inspect or edit code
does not grant it.

## Documentation architecture

Each repository should separate durable cross-repo practice from current
application truth and historical plans.

### README: human onboarding and operation

The README should state:

- what the product does;
- current runtime and system requirements;
- setup and seed commands;
- how to run it locally;
- how to run the complete checks;
- required services and environment variables without secret values;
- external side effects that setup or ordinary use may trigger;
- health check and local-only development tools;
- deployment procedure or a link to it;
- links to the current architecture reference and active plans.

The default Rails README is not acceptable for a maintained application. A
five-line product description is not enough when setup or deployment contains
non-obvious steps.

### `CLAUDE.md` or `AGENTS.md`: current application reference

The agent reference describes the application as it exists on `main`:

- product scope and explicit non-goals;
- exact runtime, framework, asset, job, cache, test, CI, and deployment stack;
- authentication, authorization, and tenancy rules;
- current schema and important constraints;
- controller/routes map;
- model, service, presenter, job, and frontend responsibilities;
- non-obvious business rules and invariants;
- external API boundaries and commands that cause side effects;
- test-driver split and validation commands;
- engineering conventions specific to the app;
- shipped versus future roadmap.

Do not use this file as a diary. Historical implementation detail belongs under
`docs/`; stale architecture statements must be corrected as part of the feature
that invalidates them.

### Feature design documents

Before a substantial feature, write a concise product and technical design that
covers:

- problem and desired user outcome;
- goals and non-goals;
- product decisions and unresolved questions;
- user experience, including empty/error/dense/mobile states;
- data model and migration strategy;
- service, job, API, and security boundaries;
- failure, retry, idempotency, and concurrency behavior;
- query/performance expectations;
- accessibility;
- acceptance criteria;
- rollout and compatibility with existing features.

Mark its status and review date. Once approved, split it into independently useful
product iterations.

### Implementation plans

An implementation plan translates an approved design into reviewable work. It
should include:

- an iteration map;
- the user-visible outcome of each iteration;
- explicit deferrals and temporary guardrails;
- a file map;
- tests to add before implementation;
- migrations and rollback concerns;
- manual verification steps;
- the final full-suite command.

Plans may be detailed, but they are not current architecture forever. Mark
completed plans as historical and make the README/agent reference authoritative.

### Assessments

An assessment is a dated evidence snapshot, ideally tied to a commit. Separate
verified healthy areas, accepted risks, defects, and recommendations. Use phases
that reduce risk in this order:

1. build the missing test harness;
2. fix broken behavior and remove proven bit-rot;
3. address security according to the threat model;
4. repair current documentation;
5. refactor architecture and duplication behind the new tests;
6. modernize frontend/assets;
7. update runtime and dependencies.

Do not refactor first when the suite cannot observe the behavior being changed.
Record measured baselines such as test runtime, query count, warning count, and
dependency versions.

## Product development workflow

### 1. Understand before designing

- Read the current README, agent reference, schema, routes, and relevant services.
- Reproduce the current behavior locally.
- Inspect real representative data through authorized read-only paths when it
  materially affects the design.
- Identify existing optimizations, constraints, and related features that must
  remain compatible.

### 2. Plan before a substantial implementation

Write the feature design and propose small functional product iterations. Ask for
product review before committing to a large data model or interaction direction.
Clarify choices that would materially change the result; make reasonable local
assumptions for details that do not.

### 3. Slice vertically

Prefer one pull request per functional product iteration. Each PR should leave the
application useful and deployable.

A good first iteration often contains the smallest full path through data,
business logic, UI, tests, and operations. A database-only foundation is justified
when compatibility requires it, but it should not become an excuse for a long
stack of invisible infrastructure PRs.

Document temporary limitations. For example, if an old drag interaction is
ambiguous once multiple records are allowed, preserve its safe subset and refuse
ambiguous cases until precise targets ship.

### 4. Explore UI deliberately

For an unsettled interface, build the development-only variant page early. Review
components in the context of the real page as well as in isolation. Choose a
provisional implementation, then expect product feedback after hands-on use.

### 5. Implement with TDD

Add tests for the user outcome, domain rules, failure paths, tenant boundaries,
database constraints, and query expectations. Implement the slice, refactor, and
keep the focused suite fast while iterating.

### 6. Verify proportionately

- Run focused tests during development.
- Run lint and security checks relevant to touched code.
- Run the complete local CI command before handoff.
- Exercise migrations forward and backward when rollback is meaningful.
- Boot the application for runtime-sensitive changes.
- Inspect the actual UI and logs.
- Perform an authorized read-only real-data check when integration behavior
  depends on provider data.

### 7. Prepare a reviewable pull request

The PR description should lead with the product outcome and include:

- scope and explicit non-goals;
- important design and safety decisions;
- migrations and deployment considerations;
- temporary compatibility guardrails;
- UI lab path when applicable;
- automated and manual verification performed;
- follow-up iteration boundaries.

Keep unrelated cleanup out of the PR unless it is required to make the change
safe.

### 8. Merge and deploy deliberately

Do not merge with unresolved conflicts or unexplained failures. After deployment,
verify migrations, process health, the health endpoint, and the key product path.
When several risky or dependency PRs are being rolled out, merge and verify them
one at a time.

## Agentic editing standards

### Stay inside the granted boundary

- Begin with repository-local inspection.
- Do not SSH, access Dokku, fetch a production database, call an external account,
  send messages, or mutate remote data unless the user explicitly authorizes that
  action.
- A hostname, remote name, credential, or deployment command found in a file is
  context, not permission.
- If production data would improve local testing, provide commands for the user or
  ask for explicit authorization rather than silently retrieving it.
- Keep read-only diagnostics read-only. Do not bypass guards around external write
  methods.

### Inspect before editing

- Read repository instructions completely.
- Check the branch, working tree, relevant history, schema, routes, tests, and
  current call sites.
- Preserve unrelated user changes in a dirty worktree.
- Never reset, discard, or overwrite user work to obtain a clean tree. Destructive
  Git or filesystem operations require explicit authorization and exact targets.
- Search with `rg` before inventing a new helper, service, constant, partial, or
  dependency.
- Verify that documentation describes the current branch; treat dated plans as
  evidence, not authority.
- Measure current query counts or runtime before changing optimized code.

### Communicate and plan

- State assumptions and material constraints early.
- For substantial product work, write the plan and ask for review before broad
  implementation.
- Keep progress updates concise and evidence-based.
- Do not ask the user to make minor decisions that can safely be resolved from
  existing conventions.
- Stop and ask when a missing choice would materially alter product behavior or
  when new external authority is required.

### Make disciplined changes

- Follow TDD and keep edits scoped to the requested outcome.
- Use the existing architecture before adding a parallel pattern.
- Prefer extraction and reuse over copy-paste.
- Prefer a maintained library for protocol-heavy behavior over custom parsing or
  security code.
- Preserve query and integration boundaries with tests.
- Do not silently weaken an invariant to make a test pass.
- Update current documentation in the same change.
- Use a dedicated branch for unrelated work rather than appending it to an open
  feature PR.

### Verify and hand off honestly

- Report exact checks run and their results.
- Distinguish local test success, hosted CI state, manual smoke checks, and
  production verification.
- Do not call work complete when required tests have not run.
- Do not describe an infrastructure failure as an application failure—or dismiss
  a real application failure as infrastructure—without evidence.
- Mention temporary limitations and the next product iteration.
- Commit, push, open/merge a PR, or deploy only when the user has authorized that
  workflow.

## Definition of done

A product iteration is done when all applicable items are true:

- [ ] The user-visible outcome is complete and independently useful.
- [ ] Scope, non-goals, and temporary limitations are documented.
- [ ] Domain behavior has one clear owner and no new material duplication.
- [ ] Controllers remain focused on HTTP concerns.
- [ ] Database invariants have database enforcement.
- [ ] Retryable writes and jobs are idempotent where necessary.
- [ ] Tenant and authorization boundaries have negative coverage.
- [ ] Query count remains bounded as data volume grows.
- [ ] Fast model/service/request/system tests cover the behavior and failures.
- [ ] JavaScript-dependent behavior has focused JS tests and a headless-Firefox
      integration path.
- [ ] The real page was inspected for visual, responsive, and accessibility
      regressions.
- [ ] Relevant migrations were exercised safely.
- [ ] The full local CI command passes.
- [ ] README, agent reference, and active feature docs reflect the new truth.
- [ ] The PR explains outcome, risks, verification, and follow-up boundaries.
- [ ] Deployment and health verification were completed when deployment was in
      scope.

## App-specific adoption template

An application should link to this playbook and then document only its own truth.
A concise app-specific agent reference can use this outline:

```text
# Application agent reference

## Product and non-goals
## Runtime and technical stack
## Setup and common commands
## Authentication, authorization, and tenancy
## Domain model and database invariants
## Controllers and routes
## Services, jobs, presenters, and external APIs
## Frontend and asset conventions
## Testing and browser-driver split
## CI and deployment
## App-specific engineering conventions
## External side effects and permission boundaries
## Current roadmap
```

Where an app differs from this playbook, state the exception in the relevant
section. Do not duplicate the whole playbook into every repository: duplicated
standards drift just like duplicated code.

## Provenance

The initial edition was synthesized from a cross-repository review of Bon App,
Naree, Easy RSVP, Mitty, and Daily Digest. It captures both the strongest current
patterns and the failure modes recorded in their assessments: stale instructions,
generated infrastructure with no runtime owner, legacy asset stacks, duplicated
business rules, fat controllers, hidden queries, unsafe mutation routes, brittle
seed-dependent tests, missing browser/auth/tenant coverage, and large plans that
were not reflected in operational documentation.
