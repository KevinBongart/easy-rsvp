# Organizer link privacy

Organizer links are bearer credentials. The application logger filters organizer
path segments and UUID-shaped values before writing messages, including request
starts, redirects, SQL diagnostics and tagged messages. Rollbar payloads receive
the same recursive filtering; its `admin_token` field is also scrubbed. Public
routes, authorization and shareable organizer links are unchanged.

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
collectors, APM configuration, or retention without deployment inspection.
Use synthetic organizer links to verify each sink. Restrict and expire historical
logs according to the operator's retention policy; do not copy real tokens into
issues or test fixtures. No historical log deletion or token rotation is performed
by this change.
