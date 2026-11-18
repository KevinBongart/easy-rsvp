require 'rails_helper'

RSpec.describe 'Search indexing of event pages', type: :request do
  def robots_meta
    Nokogiri::HTML(response.body).at_css('meta[name="robots"]')&.[]('content')
  end

  it 'keeps the home page indexable' do
    get root_path

    expect(response.headers['X-Robots-Tag']).to be_nil
    expect(robots_meta).to be_nil
  end

  it 'asks search engines not to index public event pages' do
    event = create(:event)

    get event_path(event)

    expect(response).to have_http_status(:ok)
    expect(response.headers['X-Robots-Tag']).to eq('noindex, nofollow')
    expect(robots_meta).to eq('noindex, nofollow')
  end

  it 'asks search engines not to index calendar downloads' do
    get calendar_event_path(create(:event))

    expect(response).to have_http_status(:ok)
    expect(response.headers['X-Robots-Tag']).to eq('noindex, nofollow')
  end

  it 'asks search engines not to index organizer pages' do
    event = create(:event)

    get event_admin_path(event, event.admin_token)

    expect(response).to have_http_status(:ok)
    expect(response.headers['X-Robots-Tag']).to eq('noindex, nofollow')
    expect(robots_meta).to eq('noindex, nofollow')
  end

  describe 'links in event descriptions' do
    it 'marks every link as nofollow user-generated content' do
      event = create(:event, body: '<div><a href="https://example.com/shop" rel="dofollow">Shop</a> and <a href="https://example.org">more</a></div>')

      get event_path(event)

      links = Nokogiri::HTML(response.body).css('.trix-content a')
      expect(links.map { |link| link['href'] }).to eq([ 'https://example.com/shop', 'https://example.org' ])
      expect(links.map { |link| link['rel'] }).to all(eq('nofollow ugc noopener noreferrer'))
    end

    it 'still removes unsafe markup' do
      # This markup would be flagged as spam; render it anyway to test sanitizing.
      allow(Event::SpamCheck).to receive(:spam?).and_return(false)
      event = create(:event, body: <<~HTML)
        <div>
          <script>alert(1)</script>
          <img src="https://example.com/x.png" onerror="alert(2)">
          <a href="javascript:alert(3)" onclick="alert(4)">Click</a>
          <iframe src="https://example.com"></iframe>
          <form action="https://example.com/login"><input name="password"><button>Sign in</button></form>
          <svg><circle r="10"></circle></svg>
          <div style="position:fixed;inset:0">Overlay</div>
        </div>
      HTML

      get event_path(event)

      content = Nokogiri::HTML(response.body).at_css('.trix-content')
      expect(content.css('script, iframe, form, input, button, svg')).to be_empty
      expect(content.css('[onerror], [onclick], [style]')).to be_empty
      expect(content.at_css('a')['href']).to be_nil
      expect(content.at_css('a')['rel']).to eq('nofollow ugc noopener noreferrer')
      expect(content.at_css('img')['src']).to eq('https://example.com/x.png')
    end
  end
end
