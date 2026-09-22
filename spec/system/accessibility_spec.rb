require "rails_helper"

RSpec.describe "Accessibility", type: :system, js: true do
  it "has no automated violations on the creation and public event pages" do
    visit root_path
    expect_page_to_be_accessible

    event = create(:event, title: "Accessible picnic")
    visit event_path(event)
    expect_page_to_be_accessible
  end

  it "has no automated violations on the organizer page or open RSVP modal" do
    rsvp = create(:rsvp, name: "Alex")
    visit event_admin_path(rsvp.event, rsvp.event.admin_token)
    expect_page_to_be_accessible

    find(%(a[aria-label="Edit RSVP for Alex"])).click
    expect(page).to have_css(".modal.show", style: { "opacity" => "1" })
    expect_page_to_be_accessible
  end

  it "has no automated violations on the site-wide dashboard" do
    create(:event)
    visit "http://spec-admin:spec-password@#{Capybara.current_session.server.host}:#{Capybara.current_session.server.port}/admin/events"

    expect_page_to_be_accessible
  end

  it "wraps a long title and organizer URLs at Firefox's narrow viewport" do
    event = create(:event, title: "AnUnusuallyLongEventName" * 12)
    page.current_window.resize_to(500, 844)
    visit event_admin_path(event, event.admin_token)

    expect(page.evaluate_script("window.innerWidth")).to be <= 500
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true)
    expect(page.evaluate_script("getComputedStyle(document.querySelector('#admin-link')).overflowWrap")).to eq("anywhere")
    expect(page.evaluate_script("getComputedStyle(document.querySelector('.event-heading')).overflowWrap")).to eq("anywhere")
  end
end
