require 'rails_helper'

RSpec.describe UploadSizeLimiter do
  ['/image_uploads', '/image_uploads.json'].each do |path|
    it "rejects oversized requests to #{path} before invoking Rails" do
      downstream = instance_double('Rack application')
      allow(downstream).to receive(:call)
      limiter = described_class.new(downstream)
      env = {
        'REQUEST_METHOD' => 'POST',
        'PATH_INFO' => path,
        'CONTENT_LENGTH' => (described_class::MAXIMUM_REQUEST_SIZE + 1).to_s
      }

      status, headers, body = limiter.call(env)

      expect(status).to eq(413)
      expect(headers.fetch('content-type')).to eq('application/json')
      expect(body.join).to include('request is too large')
      expect(downstream).not_to have_received(:call)
    end
  end

  it 'passes requests within the transport limit to Rails' do
    downstream = instance_double('Rack application', call: [204, {}, []])
    limiter = described_class.new(downstream)
    env = {
      'REQUEST_METHOD' => 'POST',
      'PATH_INFO' => '/image_uploads',
      'CONTENT_LENGTH' => described_class::MAXIMUM_REQUEST_SIZE.to_s
    }

    expect(limiter.call(env).first).to eq(204)
    expect(downstream).to have_received(:call).with(env)
  end
end
