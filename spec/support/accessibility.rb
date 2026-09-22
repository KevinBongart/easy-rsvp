require "axe-rspec"

module AccessibilityHelpers
  WCAG_TAGS = %i[wcag2a wcag2aa wcag21a wcag21aa wcag22aa].freeze

  def expect_page_to_be_accessible
    expect(page).to be_axe_clean.according_to(*WCAG_TAGS).skipping("target-size")

    # Sparkline points use their position to convey the data and qualify for
    # WCAG's essential target-size exception. Other rules still inspect them.
    expect(page).to be_axe_clean
      .checking_only("target-size")
      .excluding(".sparkline-hit-area")
  end
end

RSpec.configure do |config|
  config.include AccessibilityHelpers, type: :system
end
