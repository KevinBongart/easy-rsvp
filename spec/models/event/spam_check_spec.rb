require 'rails_helper'

RSpec.describe Event::SpamCheck do
  def reasons(title, html = '')
    described_class.reasons(title: title, html: html)
  end

  describe 'titles from the November 2026 spam wave' do
    {
      'NextGen Peptides working coupon code: NEX55' => :promo_code,
      'PS Peptide Promo Code GET80 – Save 25% on Online Orders' => :promo_code,
      'Simms Research Discount Code [SIMAX] – Flat 40% OFF' => :promo_code,
      'APE BORN Fitness 〖APE〗 Flat 25% Off' => :decorative_brackets,
      '𝓢𝓱𝓮𝓲𝓷 90% 𝓞𝓯𝓯 𝓟𝓻𝓸𝓶𝓸 𝓒𝓸𝓭𝓮' => :fancy_letters,
      '[NEW] Julius AI Promo Code ((KANNY))' => :code_wrapper,
      'Engwe kod rabatowy TONY00 – 100 zł taniej' => :promo_code,
      '1-888-485-3085 British Airways London Office' => :call_center_phone,
      'Best IPTV Providers 2026: Ranked & Reviewed' => :iptv,
      '7* Best iPTVServices of 2026 - Complete Comparison' => :iptv,
      'trisha______pratihari.786' => :social_handle,
      '_kanhaaa' => :social_handle,
      'kanha__ji' => :social_handle,
      '@mghtooedit1007' => :social_handle,
      'BitStarz 30 Free Spins No Deposit 2026' => :gambling,
      'Earn Robux Free Easily: Updated Methods That Actually Work' => :gambling,
      'Free Instagram Followers: The 2026 Expert Evaluation' => :followers,
      'Top 6 Anonymous Facebook Story Viewer That Really Works' => :account_viewer,
      'Keto Gummies Reviews & Complaints (We Tried It)' => :review_bait,
      'Buy Xanax Online No Rx' => :pharmacy,
      'Best Peptides for Weight Loss 2026' => :weak_topic_corroborated
    }.each do |title, reason|
      it "flags #{title.inspect} (#{reason})" do
        expect(reasons(title)).to include(reason)
      end
    end
  end

  describe 'real event titles' do
    [
      'Promotion party for Sarah!',
      'Casino Night Fundraiser 2026',
      'Casino night - $40 tickets, all proceeds to PTA',
      'Holiday Gala - Dress code: black tie',
      'Fiesta de cumpleaños - Código de vestimenta: blanco',
      'Party! Gate code is 4521#',
      'Women Who Code: Spring Hack Night',
      'Customer Service Team Lunch',
      'Retirement party - 30 years of customer care!',
      'Referral Partners Networking Mixer',
      'Peptide Chemistry Symposium 2026',
      'Followers of Christ Youth Retreat',
      'BBQ at our place - RSVP call 555-123-4567',
      'Early bird tickets 20% off until May 1',
      'Student discount night - $5 entry',
      'Redeemer Church Fall Festival - $5 hayrides',
      'Trip to Rabat - 300 € all inclusive',
      'Hot dog & video game night',
      'Movie night: full movie marathon of LOTR',
      '【2026】忘年会',
      '【ONLINE】Japanese Language Exchange',
      'Green Britain TV Launch and Promo Screening',
      "Cozy House Casino - Lucy's 29th Birthday",
      'Basement Poker Tournament',
      'Lily_5th',
      'Birthday_2026',
      'Room_101',
      'bday.2026',
      'Q4_offsite',
      '@home',
      '@Starbucks',
      'Sarah.40',
      'party.12.05',
      'Brunch.11.30',
      'Room.101',
      'v1.2.10'
    ].each do |title|
      it "accepts #{title.inspect}" do
        expect(reasons(title)).to be_empty
      end
    end
  end

  describe 'descriptions' do
    let(:paragraph) { "<div>#{'We will meet at the park entrance and walk together to the picnic area. ' * 10}</div>" }

    it 'accepts a long invitation with a few links' do
      html = (1..3).map { |day| "<div>Day #{day}: #{'We will meet at the park entrance and walk to the picnic area. ' * 10}</div>" }.join +
        "<div><a href=\"https://maps.example\">Map</a> · <a href=\"https://registry.example\">Registry</a></div>"

      expect(reasons('Anna & Ben - Wedding Weekend', html)).to be_empty
    end

    it 'does not count inline images toward the length' do
      image = %(<action-text-attachment sgid="x" content-type="image/png"><figure><img src="data:image/png;base64,#{'A' * 500_000}"></figure></action-text-attachment>)

      expect(reasons('Photo night', "#{paragraph}#{image}<div><a href=\"https://example.com\">tickets</a></div>")).to be_empty
    end

    it 'flags a long page with a link' do
      html = "#{paragraph * 6}<div><a href=\"https://shop.example\">Get the deal</a></div>"

      expect(reasons('Ultimate guide', html)).to include(:long_text_with_link)
    end

    it 'flags very long pages even without links' do
      expect(reasons('Ultimate guide', paragraph * 9)).to include(:very_long_text)
    end

    it 'flags markup the editor never produces' do
      expect(reasons('Guide', '<h2>Why it works</h2><p>Short text</p>')).to include(:non_editor_html)
    end

    it 'flags the same line repeated' do
      line = '<div>Use code SAVE25 at checkout for the best price</div>'

      expect(reasons('Deals', line * 3)).to include(:repeated_lines)
    end

    describe 'spam hidden in parts Action Text still renders' do
      let(:spam) { "#{(1..90).map { |n| "Point #{n}: the best deal on the market today." }.join(' ')} <a href=\"https://shop.example\">shop</a>" }

      it 'counts text inside a figure' do
        expect(reasons('Dinner party', "<div>Hi</div><figure><div>#{spam}</div></figure>")).to include(:long_text_with_link)
      end

      it 'counts HTML stored in a content attachment' do
        html = %(<action-text-attachment content-type="text/html" content="#{CGI.escapeHTML("<div>#{spam}</div>")}"></action-text-attachment>)

        expect(reasons('Dinner party', html)).to include(:long_text_with_link)
      end

      it 'counts attachment captions' do
        html = %(<action-text-attachment sgid="x" content-type="image/png" caption="#{CGI.escapeHTML(spam)}"></action-text-attachment><div><a href="https://shop.example">shop</a></div>)

        expect(reasons('Dinner party', html)).to include(:long_text_with_link)
      end

      it 'checks the tags inside a content attachment' do
        html = %(<action-text-attachment content-type="text/html" content="#{CGI.escapeHTML('<h2>Why</h2><p>Buy</p>')}"></action-text-attachment>)

        expect(reasons('Dinner party', html)).to include(:non_editor_html)
      end
    end

    it 'handles deeply nested markup without raising' do
      html = ('<blockquote>' * 2_000) + 'hi' + ('</blockquote>' * 2_000)

      expect { reasons('Nested', html) }.not_to raise_error
    end
  end
end
