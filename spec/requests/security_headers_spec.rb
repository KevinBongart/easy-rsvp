require "rails_helper"

RSpec.describe "Browser security headers", type: :request do
  it "enforces a content security policy compatible with the application" do
    get root_path

    directives = response.headers.fetch("Content-Security-Policy").split("; ").to_h do |directive|
      name, *sources = directive.split
      [ name, sources ]
    end
    nonce = Nokogiri::HTML(response.body).at_css('meta[name="csp-nonce"]')["content"]

    expect(directives).to include(
      "default-src" => [ "'self'" ],
      "base-uri" => [ "'self'" ],
      "connect-src" => [ "'self'", "https://s3.amazonaws.com" ],
      "form-action" => [ "'self'" ],
      "frame-ancestors" => [ "'none'" ],
      "img-src" => [ "'self'", "data:", "blob:", "https://s3.amazonaws.com" ],
      "object-src" => [ "'none'" ],
      "script-src" => [ "'self'" ],
      "script-src-attr" => [ "'none'" ],
      "style-src" => [ "'self'" ],
      "style-src-elem" => [ "'self'", "'nonce-#{nonce}'" ],
      "style-src-attr" => [ "'unsafe-inline'" ]
    )
    expect(response.headers).not_to have_key("Content-Security-Policy-Report-Only")
  end

  it "uses the modern permissions policy header" do
    get root_path

    expect(response.headers.fetch("Permissions-Policy")).to eq(
      "accelerometer=(), camera=(), clipboard-read=(), clipboard-write=(self), " \
      "display-capture=(), geolocation=(), gyroscope=(), magnetometer=(), " \
      "microphone=(), payment=(), usb=()"
    )
    expect(response.headers).not_to have_key("Feature-Policy")
  end
end
