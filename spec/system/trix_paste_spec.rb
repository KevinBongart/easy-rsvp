require 'rails_helper'

RSpec.describe 'Pasting into Trix', type: :system, js: true do
  it 'preserves pasted text while removing executable attachment content' do
    visit root_path
    fill_in 'What are you planning?', with: 'Pasted invitation'
    editor = find('trix-editor')
    editor.click
    page.execute_script(<<~'JS', editor)
      window.pasteExecuted = false;
      const attachment = JSON.stringify({contentType: 'text/html', content: '<img src="/missing-paste-image" onerror="window.pasteExecuted = true">Bring snacks'});
      const button = document.createElement('button');
      button.type = 'button';
      button.id = 'copy-paste-fixture';
      button.textContent = 'Copy paste fixture';
      const wrapper = document.createElement('div');
      wrapper.setAttribute('data-trix-attachment', attachment);
      button.addEventListener('click', () => {
        document.addEventListener('copy', event => {
          event.clipboardData.setData('text/html', '<p>Safe pasted text</p>' + wrapper.outerHTML);
          event.clipboardData.setData('text/plain', 'Safe pasted text');
          event.preventDefault();
        }, {once: true});
        document.execCommand('copy');
      });
      document.body.appendChild(button);
    JS
    click_button 'Copy paste fixture'
    editor.click
    modifier = Selenium::WebDriver::Platform.mac? ? :command : :control
    editor.send_keys([modifier, 'v'])
    expect(page).to have_css('trix-editor', text: 'Safe pasted text')
    expect(page).to have_no_css('trix-editor [onerror]', visible: :all)
    expect(page.evaluate_script('window.pasteExecuted')).to be(false)
    click_button 'Create your event, for free!'
    expect(page).to have_css('.trix-content', text: 'Safe pasted text')
  end
end
