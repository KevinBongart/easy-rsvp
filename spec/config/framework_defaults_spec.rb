require 'rails_helper'

RSpec.describe 'Framework defaults' do
  it 'loads the Rails 6.1 defaults' do
    config = Rails.application.config

    expect(config.loaded_config_version).to eq(6.1)
  end

  it 'retains the Rails 6.0 cookie and Active Record defaults' do
    config = Rails.application.config

    expect(config.action_dispatch.use_cookies_with_metadata).to be(true)
    expect(config.active_record.collection_cache_versioning).to be(true)
  end

  it 'adopts the Rails 6.1 browser-facing defaults' do
    config = Rails.application.config

    expect(config.action_dispatch.cookies_same_site_protection).to eq(:lax)
    expect(config.action_dispatch.ssl_default_redirect_status).to eq(308)
    expect(ActionView::Helpers::FormHelper.form_with_generates_remote_forms).to be(false)
    expect(ActionView::Helpers::AssetTagHelper.preload_links_header).to be(true)
  end
end
