require 'rails_helper'

describe 'admin dashboard stats', type: :feature do
  before do
    travel_to Time.zone.local(2026, 9, 8, 12)
    # Create events in different years and months
    Event.create!(title: "Old Event", date: Date.new(2021, 5, 10), created_at: Date.new(2021, 5, 10))
    Event.create!(title: "Mid Event", date: Date.new(2022, 7, 15), created_at: Date.new(2022, 7, 15))
    Event.create!(title: "Recent Event", date: Date.new(Date.today.year, 1, 20), created_at: Date.new(Date.today.year, 1, 20))
    Event.create!(title: "This Month Event", date: Date.today.beginning_of_month + 2.days, created_at: Date.today.beginning_of_month + 2.days)
    Event.create!(title: "Another This Month", date: Date.today.beginning_of_month + 10.days, created_at: Date.today.beginning_of_month + 6.days)
    Event.create!(title: "Last Month Event", date: (Date.today.beginning_of_month - 1.month) + 5.days, created_at: (Date.today.beginning_of_month - 1.month) + 5.days)
  end

  it 'shows correct stats for total, yearly, and monthly event counts' do
    # HTTP Basic Auth prompt (simulate with rack env)
    page.driver.browser.authorize(ENV['ADMIN_USER'] || 'yourusername', ENV['ADMIN_PASSWORD'] || 'yourpassword')

    visit '/admin/events'

    # Total events
    expect(page).to have_content("Total events created since May 10, 2021: 6")
    expect(page).to have_content("2021: 1")
    expect(page).to have_content("2022: 1")
    expect(page).to have_content("#{Date.today.year}: 4")

    # Last 12 completed months plus the current projection
    expect(page).to have_content("Last 12 months")
    expect(page).to have_content(Date.today.strftime("%B %Y"))
    expect(page).to have_content((Date.today - 1.month).strftime("%B %Y"))

    # This month extrapolation
    expect(page).to have_content("September 2026: 2 so far, 8 extrapolated")
    expect(page).to have_content("so far")
    expect(page).to have_content("extrapolated")
    expect(page).to have_css('#monthly-chart button[aria-label="September 2026: 2 so far; 8 extrapolated"]')
    expect(page).to have_css('#current-month-chart button[aria-label="September 30: 8 extrapolated"]')
  end
end
