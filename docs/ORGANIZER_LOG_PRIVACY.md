# Organizer link privacy

Organizer links are bearer credentials. The application logger filters organizer
path segments and UUID-shaped values before writing messages, including request
starts, redirects, SQL diagnostics and tagged messages. Honeybadger notices receive
the same recursive filtering across the request URL, message, parameters, context,
session, CGI data, local variables and details; its `admin_token` field is also
filtered by Honeybadger. Public
routes, authorization and shareable organizer links are unchanged.

This does not rewrite old logs or configure the production proxy. During an
explicitly authorized deployment, have the server operator integrate
`config/nginx/organizer-log-format.conf` into nginx's `http` context and select
`organizer_private` in every access log for this app. The fragment cannot be
dropped into a server-only include because `map` and `log_format` are
http-context directives. Validate the effective configuration before reloading;
leaving a second default access log enabled retains the original exposure. The
format omits query strings, referrers and user agents and masks organizer paths.

Nginx error logs can also include full request URLs; route these through a
redacting log processor before collection, or establish a proxy configuration
that does not record raw request URLs. This repo cannot attest to external log
collectors, Scout APM configuration, or retention without deployment inspection.
Use synthetic organizer links to verify each sink. Restrict and expire historical
logs according to the operator's retention policy; do not copy real tokens into
issues or test fixtures. No historical log deletion or token rotation is performed
by this change.

## Production evidence

Use this fixed synthetic path so the check never exposes a real event token:

```text
/organizer-log-privacy-probe/admin/11111111-2222-4333-8444-555555555555
```

After an authorized operator deploys the nginx configuration, request that path
once and export these files locally:

1. the effective nginx configuration for the Easy RSVP app;
2. an access-log sample containing the request;
3. samples from the nginx error log and each external log collector/APM sink that
   could receive request URLs.

Then run:

```sh
bin/verify-organizer-log-privacy effective-nginx.conf access.log error.log collector.log
```

The command fails when an active access log does not name the private format,
the private format includes a raw request variable, the masked probe is absent,
or any supplied sink contains the synthetic token. Keep the assessment item open
until this check passes with production evidence and the operator has reviewed
historical log retention. Repository agents must not obtain the evidence by SSH;
the owner or server operator supplies it.
