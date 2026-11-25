# Be sure to restart your server when you modify this file.

# Enforced Content Security Policy. See the Securing Rails Applications Guide:
# https://guides.rubyonrails.org/security.html#content-security-policy-header
#
# Production stores Active Storage files in the www.easy-rsvp.com S3 bucket
# (config/storage.yml). The bucket name contains dots, so the AWS SDK issues
# path-style URLs: https://s3.amazonaws.com/www.easy-rsvp.com/<key>.
s3_bucket_url = "https://s3.amazonaws.com/www.easy-rsvp.com/"

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    # Scripts come only from our own bundle: no inline scripts, handlers, or eval.
    policy.script_src :self
    # Stylesheets come from our own bundle. Trix and Turbo's progress bar insert
    # a <style> element at runtime and mark it with the nonce from csp_meta_tag.
    policy.style_src :self
    # Style attributes stay allowed: Trix reads them from pasted HTML to keep
    # formatting (Google Docs marks bold as style="font-weight: 700"), and the
    # admin sparklines position their hit areas with them. Action Text strips
    # style attributes from rendered descriptions.
    policy.style_src_attr :unsafe_inline
    # Images: our own files and Active Storage redirects to S3, data: icons in
    # Bootstrap and Trix stylesheets, blob: previews of uploads in the editor,
    # and https: images hotlinked in existing descriptions or pasted from other
    # sites, which Action Text renders as remote images.
    policy.img_src :self, :data, :blob, :https
    # Trix direct uploads PUT each file straight to the bucket.
    policy.connect_src :self, s3_bucket_url
    policy.object_src :none
    policy.base_uri :self
    policy.form_action :self
    policy.frame_ancestors :none
  end

  # A fresh random nonce per response, used only for style elements.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[style-src]
end
