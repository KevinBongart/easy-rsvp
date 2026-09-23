permissions_policy = [
  "accelerometer=()",
  "camera=()",
  "clipboard-read=()",
  "clipboard-write=(self)",
  "display-capture=()",
  "geolocation=()",
  "gyroscope=()",
  "magnetometer=()",
  "microphone=()",
  "payment=()",
  "usb=()"
].join(", ")

Rails.application.config.action_dispatch.default_headers["Permissions-Policy"] = permissions_policy
