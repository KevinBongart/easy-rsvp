Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri :self
    policy.connect_src :self, "https://s3.amazonaws.com"
    policy.font_src :self
    policy.form_action :self
    policy.frame_ancestors :none
    policy.frame_src :none
    policy.img_src :self, :data, :blob, "https://s3.amazonaws.com"
    policy.manifest_src :self
    policy.media_src :none
    policy.object_src :none
    policy.script_src :self
    policy.script_src_attr :none
    policy.style_src :self
    policy.style_src_elem :self
    policy.style_src_attr :unsafe_inline
    policy.worker_src :none
  end
end
