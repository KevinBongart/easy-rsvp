require 'rails_helper'

RSpec.describe 'Administrator charts', type: :system, js: true do
  def visit_dashboard
    visit "http://spec-admin:spec-password@#{Capybara.current_session.server.host}:#{Capybara.current_session.server.port}/admin/events"
  end

  it 'shows actual and projected numbers on hover and keyboard focus, including after navigation' do
    travel_to Time.zone.local(2026, 9, 10, 12) do
      create(:event, title: 'Chart example', created_at: Time.zone.local(2025, 1, 1))
      create_list(:event, 2, created_at: Time.zone.local(2026, 9, 2))
      visit_dashboard
      expect(page).to have_content('Total events created since January 1, 2025: 3')
      expect(page).to have_content('September 2026: 2 so far, 6 extrapolated')

      expect(page).to have_content('2026: 2 so far, 3 extrapolated')
      expect(page).to have_content('Last 12 months')
      expect(page).to have_no_content('Solid: actual')

      within('#yearly-chart') do
        find('button', match: :first).hover
        expect(page).to have_css('[role="tooltip"]', text: '2025: 1', visible: true)
        all('button')[-2].hover
        expect(page).to have_css('[role="tooltip"]', text: '2026 through September 10: 2', visible: true)
        all('button').last.hover
        expect(page).to have_css('[role="tooltip"]', text: '2026 through December 31: 3 extrapolated', visible: true)
      end
      within('#monthly-chart') do
        all('button').last.hover
        expect(page).to have_css('[role="tooltip"]', text: 'September 2026: 2 so far; 6 extrapolated', visible: true)
      end
      within('#current-month-chart') do
        find('button[aria-label="September 10: 2"]').hover
        expect(page).to have_css('[role="tooltip"]', text: 'September 10: 2', visible: true)
        # Tab between adjacent days verifies the keyboard path without a mouse hover.
        all('button')[-2].click
        send_keys :tab
        expect(page).to have_css('[role="tooltip"]', text: 'September 30: 6 extrapolated', visible: true)
      end
      expect(find('#monthly-chart .sparkline-projection').evaluate_script('getComputedStyle(this).strokeDasharray')).not_to eq('none')

      click_link 'Sort by RSVP count'
      within('#monthly-chart') do
        all('button').last.hover
        expect(page).to have_css('[role="tooltip"]', text: 'September 2026: 2 so far; 6 extrapolated', visible: true)
      end
      FileUtils.mkdir_p(Capybara.save_path)
      find('.admin-statistics').native.save_screenshot(Rails.root.join('tmp/screenshots/admin-charts-desktop.png'))
      page.current_window.resize_to(390, 844)
      find('#current-month-chart button', match: :first).click
      expect(page).to have_css('#current-month-chart [role="tooltip"]', text: 'September 1: 0', visible: true)
      expect(find('.admin-statistics').evaluate_script('this.scrollWidth <= this.clientWidth')).to be(true)
      find('.admin-statistics').native.save_screenshot(Rails.root.join('tmp/screenshots/admin-charts-mobile.png'))
    end
  end

  it 'renders empty charts without broken coordinates or hover values' do
    visit_dashboard
    expect(page).to have_css('.admin-sparkline svg', count: 3)
    within('#monthly-chart') do
      all('button').last.hover
      expect(page).to have_css('[role="tooltip"]', text: '0 so far; 0 extrapolated', visible: true)
    end
    expect(page).to have_no_css('polyline[points*="NaN"], polyline[points*="Infinity"]')
  end
end
