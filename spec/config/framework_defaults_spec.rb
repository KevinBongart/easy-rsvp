require 'rails_helper'

RSpec.describe 'Framework defaults' do
  it 'adopts the Rails 6.0 defaults used by cookies and Active Record collections' do
    config = Rails.application.config

    expect(config.loaded_config_version).to eq(6.0)
    expect(config.action_dispatch.use_cookies_with_metadata).to be(true)
    expect(config.active_record.collection_cache_versioning).to be(true)
  end
end
