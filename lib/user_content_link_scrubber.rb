# Sanitizes Action Text content exactly like Action Text's default safe list,
# then marks every remaining link as user-generated so search engines give it
# no ranking credit.
#
# Action Text ignores its tag and attribute safe lists whenever a custom
# scrubber is configured, so this scrubber carries the same lists itself.
class UserContentLinkScrubber < Rails::HTML::PermitScrubber
  LINK_REL = "nofollow ugc noopener noreferrer"

  def self.for_action_text
    sanitizer = ActionText::ContentHelper.sanitizer

    new(
      tags: ActionText::ContentHelper.allowed_tags ||
        (sanitizer.class.allowed_tags + [ ActionText::Attachment.tag_name, "figure", "figcaption" ]),
      attributes: ActionText::ContentHelper.allowed_attributes ||
        (sanitizer.class.allowed_attributes + ActionText::Attachment::ATTRIBUTES)
    )
  end

  def initialize(tags:, attributes:)
    super()
    self.tags = tags
    self.attributes = attributes
  end

  protected

  def scrub_attributes(node)
    super
    node["rel"] = LINK_REL if node.name == "a"
  end
end
