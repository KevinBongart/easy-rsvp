# Be sure to restart your server when you modify this file.

# Turns off browser features Easy RSVP never uses, for our pages and anything
# they might embed. The organizer page copies the public link with
# navigator.clipboard.writeText, so clipboard writes stay allowed for our origin.
#
# Rails' permissions_policy DSL still sends the obsolete Feature-Policy header
# and syntax, so this sets the current Permissions-Policy header directly.
Rails.application.config.action_dispatch.default_headers["Permissions-Policy"] = [
  "accelerometer=()",
  "autoplay=()",
  "camera=()",
  "clipboard-read=()",
  "clipboard-write=(self)",
  "display-capture=()",
  "encrypted-media=()",
  "fullscreen=()",
  "geolocation=()",
  "gyroscope=()",
  "hid=()",
  "magnetometer=()",
  "microphone=()",
  "midi=()",
  "payment=()",
  "publickey-credentials-get=()",
  "screen-wake-lock=()",
  "serial=()",
  "usb=()",
  "xr-spatial-tracking=()"
].join(", ")
