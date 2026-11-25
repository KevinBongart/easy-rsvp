require 'rails_helper'

# The policy is enforced, so a violation can silently break a feature. These
# flows run the real pages in Firefox and fail on any violation reported,
# even one that breaks nothing the other specs look at.
RSpec.describe 'Content Security Policy in the browser', type: :system, js: true do
  before do
    driven_by(:headless_firefox_bidi)
    page.current_window.resize_to(1400, 1000)
    record_csp_violations
  end

  def dashboard_url
    "http://spec-admin:spec-password@#{Capybara.current_session.server.host}:#{Capybara.current_session.server.port}/admin/events"
  end

  def expect_loaded_image(selector)
    expect(page).to have_css(selector, wait: 5) { |image| image.evaluate_script('this.complete && this.naturalWidth > 0') }
  end

  def paste_html(editor, html)
    editor.click
    page.execute_script(<<~'JS', html)
      const button = document.createElement('button');
      button.type = 'button';
      button.id = 'copy-paste-fixture';
      button.textContent = 'Copy paste fixture';
      button.addEventListener('click', () => {
        document.addEventListener('copy', event => {
          event.clipboardData.setData('text/html', arguments[0]);
          event.clipboardData.setData('text/plain', 'Pasted');
          event.preventDefault();
        }, {once: true});
        document.execCommand('copy');
        button.remove();
      });
      document.body.appendChild(button);
    JS
    click_button 'Copy paste fixture'
    editor.click
    editor.send_keys([ Selenium::WebDriver::Platform.mac? ? :command : :control, 'v' ])
  end

  it 'reports violations to the recorder, so a clean run means something' do
    visit root_path
    page.execute_script(<<~JS)
      const style = document.createElement('style');
      style.textContent = 'main { color: red }';
      document.head.appendChild(style);
      const script = document.createElement('script');
      script.textContent = 'window.inlineScriptRan = true';
      document.body.appendChild(script);
    JS

    expect(page.evaluate_script('window.inlineScriptRan')).to be_nil
    expect(csp_violations.map { |violation| violation['directive'] }).to include('style-src-elem', 'script-src-elem')
  end

  it 'creates, edits, and answers an event with pasted content and an uploaded image' do
    visit root_path
    fill_in 'What are you planning?', with: 'Policy picnic'
    editor = find('trix-editor')
    paste_html(editor, '<p style="color: red"><b>Bring</b> <span style="font-weight: bold">snacks</span></p>')
    expect(page).to have_css('trix-editor', text: 'Bring snacks')
    # Trix reads formatting from style attributes in pasted HTML.
    expect(page).to have_css('trix-editor strong', text: 'snacks')
    editor.drop(Rails.root.join('spec/fixtures/files/party.png').to_s)
    expect_loaded_image('trix-editor img[src*="/rails/active_storage/"]')
    click_button 'Create your event, for free!'

    # Organizer page: the uploaded image, the copy button, and Turbo visits.
    expect_loaded_image('.trix-content img')
    click_button 'Copy'
    expect(page).to have_css('button', text: /Copied|Copy failed/)
    click_link 'Edit event', match: :first
    expect_loaded_image('trix-editor img')
    expect(page).to have_css('trix-toolbar .trix-button--icon-bold')
    click_button 'Update Event'
    expect(page).to have_css('.trix-content', text: 'Bring snacks')

    # Public page and the RSVP form.
    click_link 'public-link'
    expect_loaded_image('.trix-content img')
    fill_in 'Your name:', with: 'Alex'
    click_button 'Yes'
    expect(page).to have_link('RSVP again')
    page.refresh
    expect_loaded_image('.trix-content img')

    # Organizer response modal (Bootstrap sets styles from JavaScript).
    event = Event.last
    visit event_admin_path(event, event.admin_token)
    click_link 'edit'
    expect(page).to have_css('.modal.show') do |modal|
      modal.evaluate_script('getComputedStyle(this.querySelector(".modal-dialog")).transform === "none"')
    end
    within('.modal.show') { click_button 'Close' }
    expect(page).to have_no_css('.modal.show')

    expect(csp_violations).to eq([])
  end

  it 'shows the admin dashboard, its sparklines, and an admin preview' do
    travel_to Time.zone.local(2026, 9, 10, 12) do
      create(:event, title: 'Dashboard event', created_at: Time.zone.local(2025, 1, 1))
      create_list(:event, 2, created_at: Time.zone.local(2026, 9, 2))
      create(:event, :spam, created_at: Time.zone.local(2026, 9, 3))
      visit dashboard_url
      expect(page).to have_content('September 2026: 2 so far, 6 extrapolated')

      within('#monthly-chart') do
        all('button').last.hover
        expect(page).to have_css('[role="tooltip"]', text: 'September 2026: 2 so far; 6 extrapolated', visible: true)
      end

      # The admin preview banner on the public page.
      click_link 'Dashboard event'
      expect(page).to have_button('Mark spam')
    end

    expect(csp_violations).to eq([])
  end
end
