require 'rails_helper'

RSpec.describe 'Browser security headers', type: :request do
  def csp_directives
    response.headers.fetch('Content-Security-Policy').split(/;\s*/).to_h do |directive|
      name, *sources = directive.split
      [ name, sources ]
    end
  end

  it 'enforces the content security policy with a fresh style nonce' do
    get root_path

    nonce = Nokogiri::HTML(response.body).at_css('meta[name="csp-nonce"]')['content']
    expect(nonce).to be_present
    expect(csp_directives).to eq(
      'default-src' => [ "'self'" ],
      'script-src' => [ "'self'" ],
      'style-src' => [ "'self'", "'nonce-#{nonce}'" ],
      'style-src-attr' => [ "'unsafe-inline'" ],
      'img-src' => [ "'self'", 'data:', 'blob:', 'https:' ],
      'connect-src' => [ "'self'", 'https://s3.amazonaws.com/www.easy-rsvp.com/' ],
      'object-src' => [ "'none'" ],
      'base-uri' => [ "'self'" ],
      'form-action' => [ "'self'" ],
      'frame-ancestors' => [ "'none'" ]
    )
    expect(response.headers).not_to have_key('Content-Security-Policy-Report-Only')

    get root_path
    expect(Nokogiri::HTML(response.body).at_css('meta[name="csp-nonce"]')['content']).not_to eq(nonce)
  end

  it 'allows uploads to the URL the production storage service issues' do
    configurations = ActiveSupport::ConfigurationFile.parse(Rails.root.join('config/storage.yml'))
    service = ActiveStorage::Service.configure(:amazon, configurations)
    upload_url = service.url_for_direct_upload('example-key', expires_in: 5.minutes, content_type: 'image/png',
                                               content_length: 1, checksum: 'checksum')

    get root_path

    allowed = csp_directives.fetch('connect-src').grep(/\Ahttps:/)
    expect(allowed).to contain_exactly(a_string_ending_with('/'))
    expect(upload_url).to start_with(allowed.first)
  end

  it 'sends the current Permissions-Policy header and not the obsolete Feature-Policy' do
    get root_path

    expect(response.headers.fetch('Permissions-Policy')).to eq(
      'accelerometer=(), autoplay=(), camera=(), clipboard-read=(), clipboard-write=(self), ' \
      'display-capture=(), encrypted-media=(), fullscreen=(), geolocation=(), gyroscope=(), ' \
      'hid=(), magnetometer=(), microphone=(), midi=(), payment=(), publickey-credentials-get=(), ' \
      'screen-wake-lock=(), serial=(), usb=(), xr-spatial-tracking=()'
    )
    expect(response.headers).not_to have_key('Feature-Policy')
  end
end
