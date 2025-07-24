require 'rails_helper'

describe 'admin dashboard stats', type: :feature do
  before do
    # Create events in different years and months
    Event.create!(title: "Old Event", date: Date.new(2021, 5, 10))
    Event.create!(title: "Mid Event", date: Date.new(2022, 7, 15))
    Event.create!(title: "Recent Event", date: Date.new(Date.today.year, 1, 20))
    Event.create!(title: "This Month Event", date: Date.today.beginning_of_month + 2.days)
    Event.create!(title: "Another This Month", date: Date.today.beginning_of_month + 10.days)
    Event.create!(title: "Last Month Event", date: (Date.today.beginning_of_month - 1.month) + 5.days)
  end

  it 'shows correct stats for total, yearly, and monthly event counts' do
    # HTTP Basic Auth prompt (simulate with rack env)
    page.driver.browser.authorize(ENV['ADMIN_USER'] || 'yourusername', ENV['ADMIN_PASSWORD'] || 'yourpassword')

    visit '/admin/events'

    # Total events
    expect(page).to have_content("Total events:")
    expect(page).to have_content("2021: 1")
    expect(page).to have_content("2022: 1")
    expect(page).to have_content("#{Date.today.year}: 4")

    # Last N full months (default 6)
    expect(page).to have_content("full months")
    expect(page).to have_content(Date.today.strftime("%B %Y"))
    expect(page).to have_content((Date.today - 1.month).strftime("%B %Y"))

    # This month extrapolation
    expect(page).to have_content("This month")
    expect(page).to have_content("so far")
    expect(page).to have_content("extrapolated")
  end
end
