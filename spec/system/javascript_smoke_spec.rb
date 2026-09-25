require 'rails_helper'

RSpec.describe 'Firefox JavaScript smoke', type: :system, js: true do
  def enter_details(text)
    editor = find('trix-editor')
    editor.click
    # Like Rails' rich-text test helper, use Trix's public editing API. Native
    # clicks can select an attachment caption instead of the document body.
    page.execute_script(<<~'JS', editor, text)
      const editor = arguments[0];
      editor.focus();
      editor.editor.setSelectedRange(editor.editor.getDocument().getLength() - 1);
      editor.editor.insertString("\n" + arguments[1]);
    JS
    expect(page).to have_css('trix-editor', text: text)
    expect(page).to have_css('#event_body', visible: :all) { |input| input.value.include?(text) }
  end

  def expect_loaded_image(selector)
    expect(page).to have_css(selector)
    expect(page).to have_css("#{selector}[src]")
    # Browser image loading is asynchronous, even after the markup appears.
    expect(page).to have_css(selector, wait: 5) { |image| image.evaluate_script('this.complete && this.naturalWidth > 0') }
  end

  def open_response_modal
    click_link 'edit'
    expect(page).to have_css('.modal.show') do |modal|
      modal.evaluate_script('getComputedStyle(this.querySelector(".modal-dialog")).transform === "none"')
    end
  end

  it 'creates and edits rich text through the actual Trix editor' do
    visit root_path
    fill_in 'What are you planning?', with: 'Firefox picnic'
    enter_details('Bring a picnic blanket.')
    click_button 'Create your event, for free!'
    expect(page).to have_css('.trix-content', text: 'Bring a picnic blanket.')
    click_link 'Edit event', match: :first
    expect(page).to have_css('trix-editor', text: 'Bring a picnic blanket.')
    enter_details('And a hat.')
    click_button 'Update Event'
    expect(page).to have_css('.trix-content', text: 'And a hat.')
    click_link 'public-link'
    expect(page).to have_css('.trix-content', text: 'Bring a picnic blanket.')
    expect(page).to have_css('.trix-content', text: 'And a hat.')
  end

  it 'reveals flexible time fields, detects a time zone, and requires both times' do
    visit root_path
    fill_in 'What are you planning?', with: 'Timed picnic'

    expect(page).to have_field('From', visible: :hidden)
    find('.schedule-summary', text: 'Add a time').click
    expect(page).to have_field('From', visible: :visible)
    expect(find_field('Time zone').value).to be_present

    fill_in 'From', with: '7'
    fill_in 'Time zone', with: 'Europe/Paris'
    expect(find_field('From').value).to eq('7:00 PM')
    click_button 'Create your event, for free!'
    expect(page).to have_current_path(root_path)
    expect(page).to have_content('Your event needs both a start and end time')

    fill_in 'To', with: '10'
    click_button 'Create your event, for free!'

    event = Event.order(:id).last
    expect(page).to have_current_path(event_admin_path(event, event.admin_token))
    expect(page).to have_content('7:00 PM–10:00 PM (CEST)')
  end

  it 'keeps entered times in the form but saves just the date when the schedule is closed' do
    visit root_path
    fill_in 'What are you planning?', with: 'Date-only picnic'
    find('.schedule-summary', text: 'Add a time').click
    expect(page).to have_css('.schedule-summary', text: 'Nevermind, just the date')

    fill_in 'From', with: '7'
    fill_in 'To', with: '10'
    fill_in 'Time zone', with: 'Europe/Paris'
    find('.schedule-summary', text: 'Nevermind, just the date').click

    expect(page).to have_unchecked_field('event_schedule_enabled', visible: :hidden)
    expect(page).to have_field('From', with: '7:00 PM', visible: :hidden)
    expect(page).to have_field('To', with: '10:00 PM', visible: :hidden)
    find('.schedule-summary', text: 'Add a time').click
    expect(page).to have_field('From', with: '7:00 PM')
    expect(page).to have_field('To', with: '10:00 PM')
    find('.schedule-summary', text: 'Nevermind, just the date').click
    click_button 'Create your event, for free!'

    event = Event.order(:id).last
    expect(event).not_to be_timed
    expect(event.time_zone).to be_nil
    expect(page).to have_current_path(event_admin_path(event, event.admin_token))
  end

  it 'uploads a dropped image through Trix and displays the persisted image after reload' do
    visit root_path
    fill_in 'What are you planning?', with: 'Photo picnic'
    find('trix-editor').drop(Rails.root.join('spec/fixtures/files/party.png').to_s)
    expect(page).to have_css('trix-editor img[src*="/rails/active_storage/"]')
    expect_loaded_image('trix-editor img')
    find('trix-editor figure').click
    caption = find('trix-editor .attachment__caption-editor')
    caption.click
    expect(caption.evaluate_script('getComputedStyle(this).outlineStyle')).to eq('solid')
    caption.send_keys(:tab)
    expect(page.evaluate_script('document.activeElement.matches("trix-editor .trix-button")')).to be(true)
    expect(page.evaluate_script('getComputedStyle(document.activeElement).outlineStyle')).to eq('solid')
    expect(ActiveStorage::Blob.count).to eq(1)
    expect(ActiveStorage::Blob.last.service_name).to eq('test')
    click_button 'Create your event, for free!'
    expect_loaded_image('.trix-content img')
    expect(page).to have_css('.trix-content img[src]:not([src*="/representations/"])')
    click_link 'public-link'
    page.refresh
    expect_loaded_image('.trix-content img')
    expect(ActiveStorage::Blob.last.download).to eq(File.binread(Rails.root.join('spec/fixtures/files/party.png')))
  end

  it 'keeps an existing image when an organizer edits the surrounding text' do
    visit root_path
    fill_in 'What are you planning?', with: 'Photo to keep'
    find('trix-editor').drop(Rails.root.join('spec/fixtures/files/party.png').to_s)
    expect(page).to have_css('trix-editor img[src*="/rails/active_storage/"]')
    click_button 'Create your event, for free!'
    click_link 'Edit event', match: :first
    expect_loaded_image('trix-editor img')
    enter_details('More details after uploading.')
    click_button 'Update Event'
    expect(page).to have_css('.trix-content', text: 'More details after uploading.')
    expect_loaded_image('.trix-content img')
    expect(ActiveStorage::Blob.count).to eq(1)
  end

  it 'reveals the RSVP form again and deletes an owned response using Turbo' do
    event = create(:event)
    visit event_path(event)
    fill_in 'Your name:', with: 'Alex'
    click_button 'Yes'
    expect(page).to have_link('RSVP again')
    expect(page).to have_no_field('Your name:')
    click_link 'RSVP again'
    expect(page).to have_field('Your name:')
    click_link 'x'
    expect(page).to have_no_content('Alex')
    expect(event.rsvps).to be_empty
  end

  it 'keeps organizer links off the public page when responding from the site dashboard' do
    event = create(:event, title: 'Public event from dashboard')
    visit "http://spec-admin:spec-password@#{Capybara.current_session.server.host}:#{Capybara.current_session.server.port}/admin/events"
    click_link event.title

    expect(page).to have_no_link('admin', href: event_admin_path(event, event.admin_token))
    fill_in 'Your name:', with: 'Alex'
    click_button 'Yes'

    expect(page).to have_content('Thank you for responding!')
    expect(page).to have_no_link('admin', href: event_admin_path(event, event.admin_token))
  end

  it 'updates and deletes a response through the Bootstrap organizer modal' do
    rsvp = create(:rsvp, name: 'Alex')
    visit event_admin_path(rsvp.event, rsvp.event.admin_token)
    open_response_modal
    within('.modal.show') do
      fill_in 'Name', with: 'Alexandra'
      select 'Maybe', from: 'Response'
      click_button 'Update'
    end
    expect(page).to have_content('The RSVP was updated.')
    expect(page).to have_content('Alexandra')
    expect(rsvp.reload.response).to eq('maybe')
    open_response_modal
    within('.modal.show') { accept_confirm { click_link 'Delete…' } }
    expect(page).to have_content('The RSVP was deleted.')
    expect(Rsvp.exists?(rsvp.id)).to be(false)
  end

  it 'copies the public URL through the real clipboard button' do
    event = create(:event)
    visit event_admin_path(event, event.admin_token)
    public_url = find('#public-link')[:href]
    page.execute_script(<<~JS)
      Object.defineProperty(navigator, 'clipboard', {
        configurable: true,
        value: { writeText: async (text) => { window.copiedPublicURL = text; } }
      });
    JS
    click_button 'Copy'
    expect(page).to have_button('Copied')
    expect(page).to have_css('[role="status"]', text: 'Public event link copied', visible: :all)
    expect(page.evaluate_script('window.copiedPublicURL')).to eq(public_url)
    click_link 'public-link'
    page.go_back
    expect(page).to have_button('Copy', exact: true)
    expect(find('[role="status"]', visible: :all).text(:all)).to eq('')
  end

  it 'reports clipboard failure without claiming the link was copied' do
    event = create(:event)
    visit event_admin_path(event, event.admin_token)
    page.execute_script(<<~JS)
      Object.defineProperty(navigator, 'clipboard', {
        configurable: true,
        value: { writeText: async () => { throw new Error('denied'); } }
      });
      document.execCommand = () => false;
    JS

    click_button 'Copy'

    expect(page).to have_button('Copy failed')
    expect(page).to have_css('[role="status"]', text: 'Could not copy the public event link', visible: :all)
  end

  it 'dismisses the modal without saving changes' do
    rsvp = create(:rsvp, name: 'Original name')
    visit event_admin_path(rsvp.event, rsvp.event.admin_token)
    open_response_modal
    within('.modal.show') do
      fill_in 'Name', with: 'Unsaved name'
      click_button 'Close'
    end
    expect(page).to have_no_css('.modal.show')
    page.refresh
    expect(page).to have_content('Original name')
    expect(rsvp.reload.name).to eq('Original name')
  end

  it 'dismisses a flash message through the Bootstrap alert plugin' do
    event = create(:event, :unpublished)

    visit event_path(event)
    expect(page).to have_css('.alert.show', text: 'This event is no longer viewable.')
    find('.alert .btn-close').click

    expect(page).to have_no_css('.alert')
  end

  it 'cleans an open Bootstrap modal before Turbo caches its page' do
    rsvp = create(:rsvp)
    visit event_admin_path(rsvp.event, rsvp.event.admin_token)
    open_response_modal
    expect(page).to have_css('body.modal-open, .modal-backdrop')
    expect(page.evaluate_script('document.body.style.overflow')).to eq('hidden')

    page.execute_script('Turbo.visit(arguments[0])', event_path(rsvp.event))
    expect(page).to have_current_path(event_path(rsvp.event))
    page.go_back

    expect(page).to have_current_path(event_admin_path(rsvp.event, rsvp.event.admin_token))
    expect(page).to have_no_css('body.modal-open, .modal-backdrop, .modal.show')
    expect(page.evaluate_script('document.body.style.overflow')).to eq('')

    modal = find('.modal', visible: :all)
    expect(modal['aria-hidden']).to eq('true')
    expect(modal['aria-modal']).to be_nil
    expect(modal['role']).to be_nil
  end
end
