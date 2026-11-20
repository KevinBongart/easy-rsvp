require 'rails_helper'

RSpec.describe 'Admin spam tools', type: :request do
  def page
    Nokogiri::HTML(response.body)
  end

  def row_for(title)
    page.css('tbody tr').find { |row| row.css('td')[0].css('a').text == title }
  end

  describe 'marking events as spam' do
    it 'requires the dashboard credentials' do
      event = create(:event)

      post mark_spam_admin_event_path(event)

      expect(response).to have_http_status(:unauthorized)
      expect(event.reload).not_to be_spam
    end

    it 'marks an event as final operator spam and returns to the dashboard' do
      event = create(:event, title: 'Robux tips')

      post mark_spam_admin_event_path(event), headers: dashboard_headers.merge('HTTP_REFERER' => admin_events_url(sort: 'rsvps'))

      expect(response).to redirect_to(admin_events_url(sort: 'rsvps'))
      expect(event.reload).to have_attributes(spam_source: 'operator', spam_at: be_present, spam_decided_at: be_present)
      get event_admin_path(event, event.admin_token)
      expect(response).to have_http_status(:gone)
    end

    it 'turns an automatic flag into a final mark and keeps its time' do
      event = create(:event, :flagged_as_spam)
      flagged_at = event.reload.spam_at

      post mark_spam_admin_event_path(event), headers: dashboard_headers

      expect(event.reload).to have_attributes(spam_source: 'operator', spam_at: flagged_at)
    end

    it 'restores an event marked by mistake' do
      event = create(:event, :spam)

      post unmark_spam_admin_event_path(event), headers: dashboard_headers

      expect(event.reload).to have_attributes(spam_source: 'cleared', spam_at: nil, spam_decided_at: be_present)
      get event_path(event)
      expect(response).to have_http_status(:ok)
    end

    it 'remembers that a restored event is not spam when its organizer edits it' do
      event = create(:event, :flagged_as_spam, title: 'Casino night - buy tickets online')

      post unmark_spam_admin_event_path(event), headers: dashboard_headers
      patch event_admin_path(event, event.admin_token), params: { event: { title: 'Casino night - buy tickets online today' } }

      expect(event.reload).to have_attributes(spam_source: 'cleared', spam_at: nil)
      get event_path(event)
      expect(response).to have_http_status(:ok)
    end

    it 'lets the admin lock or restore an automatically flagged event' do
      create(:event, :flagged_as_spam, title: 'Possible bake sale spam')

      get admin_events_path, params: { spam: '1' }, headers: dashboard_headers

      actions = row_for('Possible bake sale spam').css('td')[-1].css('button').map { |button| button['formaction'].split('/').last }
      expect(actions).to eq(%w[mark_spam unmark_spam])
    end

    it 'offers a confirmed link-style button after the admin link and Jev score' do
      create(:event, title: 'Garden party')

      get admin_events_path, headers: dashboard_headers

      cells = row_for('Garden party').css('td')
      expect(cells[-3].at_css('a')['href']).to include('/admin/')
      button = cells[-1].at_css('button')
      expect(button['formaction']).to end_with('/mark_spam')
      expect(button['data-turbo-confirm']).to include('Mark “Garden party” as spam?')
      expect(button['class']).to include('btn-link')
      shared_form = page.at_css("form##{button['form']}")
      expect(shared_form['method']).to eq('post')
      expect(cells[-1].css('form')).to be_empty
    end

    it 'offers to restore events in the spam list' do
      create(:event, :spam, title: 'Peptides coupon code')

      get admin_events_path, params: { spam: '1' }, headers: dashboard_headers

      button = row_for('Peptides coupon code').css('td')[-1].at_css('button')
      expect(button['formaction']).to end_with('/unmark_spam')
      expect(button['data-turbo-confirm']).to include('Restore')
    end
  end

  describe 'creation time on the spam page' do
    it 'shows when each spam event was created, only in the spam list' do
      travel_to Time.utc(2026, 11, 18, 11, 34) do
        create(:event, :spam, title: 'Peptides coupon code')
        create(:event, title: 'Garden party')
      end

      get admin_events_path, params: { spam: '1' }, headers: dashboard_headers
      expect(page.css('thead th').map(&:text)).to include('Created')
      expect(row_for('Peptides coupon code').text).to include('2026-11-18 11:34 UTC')

      get admin_events_path, headers: dashboard_headers
      expect(page.css('thead th').map(&:text)).not_to include('Created')
    end
  end

  describe 'admin session' do
    let(:event) { create(:event, :spam, title: 'Peptides coupon code') }

    def open_admin_session
      get admin_events_path, headers: dashboard_headers
    end

    it 'shows guests and visitors without an admin session the normal pages' do
      get event_path(event)
      expect(response).to have_http_status(:gone)

      published = create(:event)
      get event_path(published)
      expect(page.at_css('#admin-preview')).to be_nil
    end

    it 'links events from the dashboard without tokens in the URL' do
      event
      open_admin_session

      get admin_events_path, params: { spam: '1' }, headers: dashboard_headers
      links = row_for('Peptides coupon code').css('a').map { |link| link['href'] }
      expect(links).to include("/#{event.hashid}", "/#{event.hashid}/admin/#{event.admin_token}")
      expect(links.join).not_to include('token=')
    end

    it 'shows the public page of a spam event to the admin' do
      open_admin_session
      get event_path(event)

      expect(response).to have_http_status(:ok)
      expect(page.at_css('#admin-preview').text).to include('marked as spam')
      expect(response.body).to include(event.title)
      expect(response.headers['X-Robots-Tag']).to eq('noindex, nofollow')
    end

    it 'shows unpublished events instead of redirecting' do
      unpublished = create(:event, :unpublished)
      open_admin_session

      get event_path(unpublished)

      expect(response).to have_http_status(:ok)
      expect(page.at_css('#admin-preview').text).to include('unpublished')
    end

    it 'shows the locked organizer page, read-only' do
      open_admin_session
      get event_admin_path(event, event.admin_token)
      expect(response).to have_http_status(:ok)
      expect(page.at_css('#admin-preview')).to be_present

      patch event_admin_path(event, event.admin_token), params: { event: { title: 'Changed' } }
      expect(response).to have_http_status(:gone)

      post toggle_publish_event_admin_path(event, event.admin_token)
      expect(response).to have_http_status(:gone)
      expect(event.reload).to have_attributes(title: 'Peptides coupon code', published: true)
    end

    it 'shows the banner on organizer pages of every hidden event' do
      open_admin_session

      [ create(:event, :unpublished), create(:event, :flagged_as_spam) ].each do |hidden|
        get event_admin_path(hidden, hidden.admin_token)
        expect(response).to have_http_status(:ok)
        expect(page.at_css('#admin-preview')).to be_present
      end
    end

    it 'expires after a day' do
      open_admin_session

      travel AdminPreview::EXPIRES_IN + 1.minute do
        get event_path(event)
        expect(response).to have_http_status(:gone)
      end
    end

    it 'closes from the dashboard footer' do
      open_admin_session
      form = page.css('form').find { |f| f['action'] == close_session_admin_events_path }
      expect(form.at_css('button').text).to eq('Close admin session')

      delete close_session_admin_events_path, headers: dashboard_headers

      expect(response).to redirect_to(root_path)
      get event_path(event)
      expect(response).to have_http_status(:gone)
    end

    describe 'spam buttons on admin pages' do
      let(:published) { create(:event, title: 'Garden party') }

      it 'marks the event and returns to the same page' do
        open_admin_session
        get event_path(published)
        form = page.at_css('#admin-preview form')
        expect(form['data-turbo-confirm']).to include('Mark “Garden party” as spam?')
        return_to = form.at_css('input[name="return_to"]')['value']
        expect(return_to).to eq(event_path(published))

        post mark_spam_admin_event_path(published), params: { return_to: return_to }, headers: dashboard_headers

        expect(response).to redirect_to(event_path(published))
        expect(published.reload.spam_source).to eq('operator')
        follow_redirect!
        expect(response).to have_http_status(:ok)
        expect(page.at_css('#admin-preview').text).to include('marked as spam')
        expect(page.at_css('#flash_notice').text).to include('was marked as spam')
        expect(page.css('#admin-preview form').map { |f| f['action'] }).to eq([ unmark_spam_admin_event_path(published) ])
      end

      it 'offers the buttons on organizer pages too' do
        open_admin_session
        get event_admin_path(published, published.admin_token)

        expect(page.at_css('#admin-preview form')['action']).to eq(mark_spam_admin_event_path(published))
      end

      it 'never redirects outside the site' do
        [ 'https://evil.example/', '//evil.example/', '/\\evil.example' ].each do |target|
          post mark_spam_admin_event_path(published), params: { return_to: target }, headers: dashboard_headers

          expect(response.location).to start_with('http://www.example.com/'), "#{target.inspect} -> #{response.location}"
        end
      end

      it 'still requires the dashboard credentials' do
        post mark_spam_admin_event_path(published), params: { return_to: event_path(published) }

        expect(response).to have_http_status(:unauthorized)
        expect(published.reload).not_to be_spam
      end
    end
  end
end
