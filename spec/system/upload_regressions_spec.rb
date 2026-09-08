require 'rails_helper'

RSpec.describe 'Upload lifecycle regressions', type: :system, js: true do
  it 'uploads once after repeated Turbolinks lifecycle events' do
    visit root_path
    page.execute_script(<<~JS)
      window.uploadStarts = 0;
      const originalOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url) {
        if (method === 'POST' && url === '/image_uploads') window.uploadStarts += 1;
        return originalOpen.apply(this, arguments);
      };
      for (let i = 0; i < 3; i++) document.dispatchEvent(new Event('turbolinks:load'));
    JS
    find('trix-editor').drop(Rails.root.join('spec/fixtures/files/party.png').to_s)
    expect(page).to have_css('trix-editor img[src*="/rails/active_storage/"]')
    expect(page.evaluate_script('window.uploadStarts')).to eq(1)
  end

  it 'uploads only once after navigating between organizer, edit, and new pages' do
    event = create(:event)
    visit event_admin_path(event, event.admin_token)
    page.execute_script("window.specDocumentMarker = 'same-document'")
    click_link 'Edit', match: :first
    expect(page).to have_button('Update Event')
    find('.navbar-brand').click
    expect(page).to have_button('Create your event, for free!')
    page.go_back
    expect(page).to have_button('Update Event')
    find('.navbar-brand').click
    expect(page).to have_button('Create your event, for free!')
    expect(page.evaluate_script('window.specDocumentMarker')).to eq('same-document')
    find('trix-editor').drop(Rails.root.join('spec/fixtures/files/party.png').to_s)
    expect(page).to have_css('trix-editor img[src*="/rails/active_storage/"]')
    expect(ImageUpload.count).to eq(1)
    expect(page.evaluate_script('typeof window.xhr')).to eq('undefined')
  end

  it 'shows a rejected upload and permits a successful retry with a real image' do
    visit root_path
    find('trix-editor').drop(Rails.root.join('spec/fixtures/files/notes.txt').to_s)
    expect(page).to have_css('[role=alert]', text: 'Image upload failed')
    expect(ImageUpload.count).to eq(0)
    find('trix-editor').drop(Rails.root.join('spec/fixtures/files/party.png').to_s)
    expect(page).to have_css('trix-editor img[src*="/rails/active_storage/"]')
    expect(page).to have_no_css('.trix-upload-error')
    expect(ImageUpload.count).to eq(1)
  end

  %w[error timeout invalid_json].each do |failure|
    it "recovers from an upload #{failure} without leaving a stuck attachment" do
      visit root_path
      # Inject only the failed transport; the retry uses the real endpoint/storage.
      page.execute_script(<<~JS, failure)
        const failure = arguments[0];
        const originalOpen = XMLHttpRequest.prototype.open;
        const originalSend = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.open = function(method, url) {
          this.specUpload = method === 'POST' && url === '/image_uploads';
          return originalOpen.apply(this, arguments);
        };
        XMLHttpRequest.prototype.send = function() {
          if (!this.specUpload) return originalSend.apply(this, arguments);
          XMLHttpRequest.prototype.open = originalOpen;
          XMLHttpRequest.prototype.send = originalSend;
          if (failure === 'invalid_json') {
            Object.defineProperty(this, 'status', { value: 200 });
            Object.defineProperty(this, 'responseText', { value: 'broken json' });
            this.dispatchEvent(new Event('load'));
          } else {
            this.dispatchEvent(new Event(failure));
          }
        };
      JS
      find('trix-editor').drop(Rails.root.join('spec/fixtures/files/party.png').to_s)
      expect(page).to have_css('[role=alert]', text: 'Image upload failed')
      expect(page).to have_no_css('trix-editor figure')
      expect(ImageUpload.count).to eq(0)
      find('trix-editor').drop(Rails.root.join('spec/fixtures/files/party.png').to_s)
      expect(page).to have_css('trix-editor img[src*="/rails/active_storage/"]')
      expect(page).to have_no_css('.trix-upload-error')
      expect(ImageUpload.count).to eq(1)
    end
  end

end
