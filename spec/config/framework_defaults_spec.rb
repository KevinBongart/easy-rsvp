require 'rails_helper'

RSpec.describe 'Framework defaults' do
  it 'loads the selected framework defaults' do
    config = Rails.application.config

    expect(config.loaded_config_version).to eq(7.2)
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

  it 'adopts the Rails 7.0 browser and redirect defaults' do
    config = Rails.application.config

    expect(config.action_dispatch.cookies_serializer).to eq(:json)
    expect(config.action_dispatch.default_headers['Referrer-Policy']).to eq('strict-origin-when-cross-origin')
    expect(config.action_controller.action_on_open_redirect).to eq(:raise)
  end

  it 'preserves the digest used to sign existing cookies and Action Text attachment SGIDs' do
    config = Rails.application.config

    expect(config.active_support.hash_digest_class).to eq(OpenSSL::Digest::SHA256)
    expect(config.active_support.key_generator_hash_digest_class).to eq(OpenSSL::Digest::SHA1)
  end

  it 'adopts the Rails 7.1 serialization defaults with legacy message fallback' do
    config = Rails.application.config

    expect(config.active_support.message_serializer).to eq(:json_allow_marshal)
    expect(config.active_support.use_message_serializer_for_metadata).to be(true)
    expect(config.active_support.raise_on_invalid_cache_expiration_time).to be(true)
  end

  it 'adopts the Rails 7.1 loading and transaction defaults' do
    config = Rails.application.config

    expect(config.add_autoload_paths_to_load_path).to be(false)
    expect(config.active_record.run_after_transaction_callbacks_in_order_defined).to be(true)
  end

  it 'adopts the Rails 7.2 PostgreSQL and Active Storage defaults' do
    config = Rails.application.config

    expect(config.yjit).to be(true)
    expect(config.active_record.postgresql_adapter_decode_dates).to be(true)
    expect(config.active_record.validate_migration_timestamps).to be(true)
    expect(config.active_storage.web_image_content_types).to include('image/webp')
  end
end
