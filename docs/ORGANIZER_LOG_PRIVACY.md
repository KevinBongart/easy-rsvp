# Organizer link privacy

Organizer links are bearer credentials. The application logger filters organizer
path segments and UUID-shaped values before writing messages, including request
starts, redirects, SQL diagnostics and tagged messages. Honeybadger notices receive
the same recursive filtering across the request URL, message, parameters, context,
session, CGI data, local variables, details and breadcrumbs (the request path in
`process_action` breadcrumbs and log-message breadcrumbs such as `Started GET`);
its `admin_token` field is also filtered by Honeybadger. Public
routes, authorization and shareable organizer links are unchanged.

Event descriptions (`body`) and guest names (`name`) are filtered parameters, so
Rails request logs, SQL bind logs and Honeybadger notices show `[FILTERED]`.
`config/honeybadger.yml` repeats both keys for notices raised outside a request.
Event titles stay readable because every public event URL already contains one.

Scout APM, when `SCOUT_APM_API_KEY` is set, labels slow-request traces with the
request path. `config/initializers/organizer_log_privacy.rb` replaces that label
with the redacted path when Rails starts processing the action. Scout's error
service is turned off in `config/scout_apm.yml`: its reports would carry the raw
request URL, the referer and an unfiltered `admin_token` parameter (it matches
filtered keys exactly), and Honeybadger already reports errors.

This does not rewrite old logs or configure the production proxy. During an
explicitly authorized deployment, include `config/nginx/organizer-log-format.conf`
in nginx's `http` context and select `organizer_private` in the site's `access_log`
directive. Validate with `nginx -t` before reloading. Check every effective
`access_log` destination, including Dokku-generated configuration; leaving a
second default access log enabled retains the original exposure. The format
omits query strings, referrers and user agents and masks organizer paths.

Nginx error logs can also include full request URLs; route these through a
redacting log processor before collection, or establish a proxy configuration
that does not record raw request URLs. This repo cannot attest to external log
collectors, Scout settings overridden by `SCOUT_*` environment variables, or
retention without deployment inspection.
Use synthetic organizer links to verify each sink. Restrict and expire historical
logs according to the operator's retention policy; do not copy real tokens into
issues or test fixtures. No historical log deletion or token rotation is performed
by this change.
