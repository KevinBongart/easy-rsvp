module RequestHelpers
  def dashboard_headers
    { 'HTTP_AUTHORIZATION' => ActionController::HttpAuthentication::Basic.encode_credentials('spec-admin', 'spec-password') }
  end

  def uploaded_image
    Rack::Test::UploadedFile.new(Rails.root.join('spec/fixtures/files/party.png'), 'image/png')
  end
end

RSpec.configure do |config|
  config.include RequestHelpers, type: :request
end
