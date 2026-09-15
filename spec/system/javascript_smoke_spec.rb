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
    click_link 'Edit', match: :first
    expect(page).to have_css('trix-editor', text: 'Bring a picnic blanket.')
    enter_details('And a hat.')
    click_button 'Update Event'
    expect(page).to have_css('.trix-content', text: 'And a hat.')
    click_link 'public-link'
    expect(page).to have_css('.trix-content', text: 'Bring a picnic blanket.')
    expect(page).to have_css('.trix-content', text: 'And a hat.')
  end

  it 'uploads a dropped image through Trix and displays the persisted image after reload' do
    visit root_path
    fill_in 'What are you planning?', with: 'Photo picnic'
    find('trix-editor').drop(Rails.root.join('spec/fixtures/files/party.png').to_s)
    expect(page).to have_css('trix-editor img[src*="/rails/active_storage/"]')
    expect_loaded_image('trix-editor img')
    expect(ActiveStorage::Blob.count).to eq(1)
    expect(ActiveStorage::Blob.last.service_name).to eq('test')
    click_button 'Create your event, for free!'
    expect_loaded_image('.trix-content img')
    expect(find('.trix-content img')[:src]).not_to include('/representations/')
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
    click_link 'Edit', match: :first
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
    expect(page.evaluate_script('window.copiedPublicURL')).to eq(public_url)
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

    page.execute_script('Turbo.visit(arguments[0])', event_path(rsvp.event))
    expect(page).to have_current_path(event_path(rsvp.event))
    page.go_back

    expect(page).to have_current_path(event_admin_path(rsvp.event, rsvp.event.admin_token))
    expect(page).to have_no_css('body.modal-open, .modal-backdrop, .modal.show')
  end
end
