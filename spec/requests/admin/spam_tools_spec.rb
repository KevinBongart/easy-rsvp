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
      expect(event.reload).to have_attributes(spam_source: 'operator', spam_at: be_present)
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

      expect(event.reload).to have_attributes(spam_source: 'cleared', spam_at: nil)
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

      actions = row_for('Possible bake sale spam').css('td')[-1].css('form').map { |form| form['action'].split('/').last }
      expect(actions).to eq(%w[mark_spam unmark_spam])
    end

    it 'offers a confirmed link-style button next to the admin link' do
      create(:event, title: 'Garden party')

      get admin_events_path, headers: dashboard_headers

      cells = row_for('Garden party').css('td')
      expect(cells[-2].at_css('a')['href']).to include('/admin/')
      form = cells[-1].at_css('form')
      expect(form['action']).to end_with('/mark_spam')
      expect(form['data-turbo-confirm']).to include('Mark “Garden party” as spam?')
      expect(form.at_css('button')['class']).to include('btn-link')
    end

    it 'offers to restore events in the spam list' do
      create(:event, :spam, title: 'Peptides coupon code')

      get admin_events_path, params: { spam: '1' }, headers: dashboard_headers

      form = row_for('Peptides coupon code').css('td')[-1].at_css('form')
      expect(form['action']).to end_with('/unmark_spam')
      expect(form['data-turbo-confirm']).to include('Restore')
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

  describe 'admin previews' do
    let(:event) { create(:event, :spam, title: 'Peptides coupon code') }
    let(:token) { AdminPreview.token_for(event) }

    it 'links spam events from the dashboard with a preview token' do
      event

      get admin_events_path, params: { spam: '1' }, headers: dashboard_headers

      links = row_for('Peptides coupon code').css('a').map { |link| link['href'] }
      expect(links).to include(a_string_including("#{event_path(event)}?preview_token="))
      expect(links).to include(a_string_including("#{event_admin_path(event, event.admin_token)}?preview_token="))
    end

    it 'does not add tokens to ordinary published events' do
      create(:event, title: 'Garden party')

      get admin_events_path, headers: dashboard_headers

      expect(row_for('Garden party').css('a').map { |link| link['href'] }).to all(satisfy { |href| !href.include?('preview_token') })
    end

    it 'shows the public page of a spam event with a valid token' do
      get event_path(event, preview_token: token)

      expect(response).to have_http_status(:ok)
      expect(page.at_css('#admin-preview').text).to include('marked as spam')
      expect(response.body).to include(event.title)
      expect(response.headers['X-Robots-Tag']).to eq('noindex, nofollow')
    end

    it 'shows the locked organizer page with a valid token, read-only' do
      get event_admin_path(event, event.admin_token, preview_token: token)
      expect(response).to have_http_status(:ok)
      expect(page.at_css('#admin-preview')).to be_present

      patch event_admin_path(event, event.admin_token, preview_token: token), params: { event: { title: 'Changed' } }
      expect(response).to have_http_status(:gone)

      post toggle_publish_event_admin_path(event, event.admin_token, preview_token: token)
      expect(response).to have_http_status(:gone)
      expect(event.reload).to have_attributes(title: 'Peptides coupon code', published: true)
    end

    it 'shows the banner on organizer previews of every hidden event' do
      unpublished = create(:event, :unpublished)
      flagged = create(:event, :flagged_as_spam)

      [ unpublished, flagged ].each do |hidden|
        get event_admin_path(hidden, hidden.admin_token, preview_token: AdminPreview.token_for(hidden))
        expect(response).to have_http_status(:ok)
        expect(page.at_css('#admin-preview')).to be_present
      end
    end

    it 'keeps the token out of Referer headers sent from preview pages' do
      get event_path(event, preview_token: token)
      expect(response.headers['Referrer-Policy']).to eq('no-referrer')

      get event_path(create(:event))
      expect(response.headers['Referrer-Policy']).not_to eq('no-referrer')
    end

    it 'shows unpublished events instead of redirecting' do
      unpublished = create(:event, :unpublished)

      get event_path(unpublished, preview_token: AdminPreview.token_for(unpublished))

      expect(response).to have_http_status(:ok)
      expect(page.at_css('#admin-preview').text).to include('unpublished')
    end

    it 'rejects missing, tampered, foreign, and expired tokens' do
      other = create(:event, :spam)

      [ nil, "#{token}x", AdminPreview.token_for(other) ].each do |bad_token|
        get event_path(event, preview_token: bad_token)
        expect(response).to have_http_status(:gone)
      end

      get event_path(event, preview_token: [ token ])
      expect(response).to have_http_status(:gone)

      expired = token
      travel AdminPreview::EXPIRES_IN + 1.minute do
        get event_path(event, preview_token: expired)
        expect(response).to have_http_status(:gone)
      end
    end

    it 'keeps preview tokens out of request logs' do
      env = Rack::MockRequest.env_for("#{event_path(event)}?preview_token=#{token}")
      env['action_dispatch.parameter_filter'] = Rails.application.config.filter_parameters

      expect(ActionDispatch::Request.new(env).filtered_path).to eq("#{event_path(event)}?preview_token=[FILTERED]")
    end
  end
end
