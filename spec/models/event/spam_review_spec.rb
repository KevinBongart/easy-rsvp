require 'rails_helper'

RSpec.describe Event::SpamReview do
  around do |example|
    previous = ENV['TYPESAFE_API_KEY']
    ENV['TYPESAFE_API_KEY'] = 'test-key'
    example.run
  ensure
    ENV['TYPESAFE_API_KEY'] = previous
  end

  def stub_jev(score: 0.1, status: 200)
    stub_request(:post, 'https://api.typesafe.ai/v1/systemone')
      .to_return(status:, body: { answers: { advertising: { noul: score } } }.to_json)
  end

  def sent_body
    body = nil
    expect(a_request(:post, 'https://api.typesafe.ai/v1/systemone').with { |request| body = JSON.parse(request.body) }).to have_been_made
    body
  end

  it 'sends a masked copy of the page and returns the score' do
    stub_jev(score: 0.97)
    event = create(:event, title: 'Call +1 (888) 555-0199 now',
      body: '<div>Write to deals@example.com or visit <a href="https://shop.example.com/x?ref=1">https://shop.example.com/x?ref=1</a> at 12 Main Street</div>')

    expect(described_class.score(event)).to eq(0.97)

    body = sent_body
    expect(body['model']).to eq('jev-latest')
    expect(body['state']['title']).to eq('Call [phone] now')
    expect(body['state']['description']).to eq('Write to [email] or visit [link to shop.example.com] at [address]')
    expect(body.to_json).not_to include('deals@example.com', '555-0199', 'ref=1', 'Main Street')
    expect(a_request(:post, 'https://api.typesafe.ai/v1/systemone').with(headers: { 'Authorization' => 'Bearer test-key' })).to have_been_made
  end

  it 'teaches Jev with the latest admin decisions in both directions' do
    stub_jev
    create(:event, title: 'Old cleared bake sale', spam_source: 'cleared', updated_at: 2.days.ago)
    create(:event, title: 'Newest cleared moving sale', spam_source: 'cleared', updated_at: 1.hour.ago)
    create(:event, :spam, title: 'Peptides coupon code')
    create(:event, :flagged_as_spam, title: 'Only automatically flagged')
    event = create(:event, title: 'Garage sale')

    stub_const("#{described_class}::EXAMPLES_PER_KIND", 1)
    described_class.score(event)

    instructions = sent_body.dig('questions', 'advertising', 'instructions')
    expect(instructions).to start_with(described_class::QUESTION)
    expect(instructions).to match(/genuine event pages, not advertising:\n- Title: Newest cleared moving sale/)
    expect(instructions).to match(/confirmed these pages are advertising spam:\n- Title: Peptides coupon code/)
    expect(instructions).not_to include('Old cleared bake sale', 'Only automatically flagged', 'Garage sale')
  end

  it 'never uses the reviewed event as its own example' do
    stub_jev
    event = create(:event, title: 'Cleared once', spam_source: 'cleared')

    described_class.score(event)

    expect(sent_body.dig('questions', 'advertising', 'instructions')).to eq(described_class::QUESTION)
  end

  it 'fails open on API errors and timeouts' do
    event = create(:event)
    allow(Rails.error).to receive(:report)

    stub_jev(status: 529)
    expect(described_class.score(event)).to be_nil

    stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_timeout
    expect(described_class.score(event)).to be_nil

    stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return(status: 200, body: '{"answers":{}}')
    expect(described_class.score(event)).to be_nil

    expect(Rails.error).to have_received(:report).exactly(3).times
  end

  it 'stays off without an API key' do
    ENV['TYPESAFE_API_KEY'] = nil
    event = create(:event)

    expect(described_class.score(event)).to be_nil
    expect(a_request(:post, 'https://api.typesafe.ai/v1/systemone')).not_to have_been_made
  end
end
