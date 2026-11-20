require 'rails_helper'

RSpec.describe 'Automatic spam flagging', type: :request do
  let(:spam_title) { 'NextGen Peptides working coupon code: NEX55 – 25% Off' }

  def create_event(title:, body: '<div>Bring a dish</div>')
    post events_path, params: { event: { title: title, date: '2026-12-24', body: body } }
    Event.order(:id).last
  end

  it 'accepts a spam-looking event like any other but hides it from guests' do
    event = create_event(title: spam_title)

    expect(response).to redirect_to(event_admin_path(event, event.admin_token))
    expect(event).to have_attributes(spam_source: 'automatic', spam_at: be_present)

    reset! # a guest's browser
    get event_path(event)
    expect(response).to have_http_status(:gone)

    post event_rsvps_path(event), params: { rsvp: { name: 'Guest' }, commit: 'Yes' }
    expect(response).to have_http_status(:gone)
  end

  it 'tells the organizer of a less certain flag that guests cannot see the event, but not why' do
    event = create_event(title: 'Robux generator')
    expect(event).to be_flagged_as_spam

    get event_admin_path(event, event.admin_token)

    expect(response).to have_http_status(:ok)
    expect(response.headers['X-Robots-Tag']).to eq('noindex, nofollow')
    page = Nokogiri::HTML(response.body)
    notice = page.at_css('#spam-notice[role="status"]').text.squish
    expect(notice).to eq("Your guests can't see this event yet. Easy RSVP's automatic spam filter is holding it. " \
                         'If this is a real event, editing it runs the check again.')
    expect(response.body).not_to match(/advertising|promotional/i)
    expect(page.at_css('a[href$=".ics"]')).to be_nil

    get edit_event_admin_path(event, event.admin_token)
    expect(Nokogiri::HTML(response.body).at_css('#spam-notice').text).to include('automatic spam filter')
    expect(response.body).not_to match(/advertising|promotional/i)
  end

  it 'publishes the event once the organizer edits it into something that does not look like spam' do
    event = create_event(title: spam_title)

    patch event_admin_path(event, event.admin_token), params: { event: { title: 'Lab holiday dinner' } }

    expect(event.reload).to have_attributes(spam_source: nil, spam_at: nil)
    get event_path(event)
    expect(response).to have_http_status(:ok)

    get event_admin_path(event, event.admin_token)
    expect(Nokogiri::HTML(response.body).at_css('#spam-notice')).to be_nil
  end

  it 'flags an event when spam is edited in after creation' do
    event = create_event(title: 'Garden party')
    expect(event).not_to be_spam

    patch event_admin_path(event, event.admin_token), params: { event: { title: spam_title } }

    expect(event.reload).to be_flagged_as_spam
    reset! # a guest's browser
    get event_path(event)
    expect(response).to have_http_status(:gone)
  end

  it 'keeps the original flag time when an edit still looks like spam' do
    event = create_event(title: spam_title)
    flagged_at = event.spam_at

    travel 1.hour do
      patch event_admin_path(event, event.admin_token), params: { event: { title: "#{spam_title} today" } }
    end

    expect(event.reload.spam_at).to eq(flagged_at)
  end

  it 'leaves the flag alone when only the publication changes' do
    event = create_event(title: spam_title)
    expect(Event::SpamCheck).not_to receive(:spam?)

    post toggle_publish_event_admin_path(event, event.admin_token)

    expect(event.reload).to have_attributes(published: false, spam_source: 'automatic')
  end

  it 'never lets edits clear an operator mark' do
    event = create(:event, :spam, title: 'Garden party')
    marked_at = event.spam_at

    event.update!(title: 'Robux generator')
    event.update!(title: 'Another garden party')

    expect(event.reload).to have_attributes(spam_source: 'operator', spam_at: marked_at)
  end
end
