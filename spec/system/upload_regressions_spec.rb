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
    pending 'Assessment 1.7: every turbolinks:load registers another upload handler'
    expect(page.evaluate_script('window.uploadStarts')).to eq(1)
  end
end
