require 'rails_helper'
require 'rake'

RSpec.describe 'image_uploads:purge_abandoned' do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?('image_uploads:purge_abandoned')
  end

  let(:task) { Rake::Task['image_uploads:purge_abandoned'] }

  before { task.reenable }

  it 'reports and removes uploads whose managed claim window elapsed' do
    upload = ImageUpload.new(upload_session_digest: ImageUpload.digest_token('abandoned'))
    upload.image.attach(
      io: File.open(Rails.root.join('spec/fixtures/files/party.png')),
      filename: 'party.png',
      content_type: 'image/png'
    )
    upload.save!
    upload.update_column(:created_at, 24.hours.ago - 1.second)

    expect { task.invoke }.to output("Purged 1 abandoned image upload.\n").to_stdout

    expect(ImageUpload.exists?(upload.id)).to be(false)
  end

  it 'refuses to run against a development database that may be imported' do
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('development'))

    expect { task.invoke }
      .to raise_error(SystemExit)
      .and output(/Refusing to purge outside production/).to_stderr
  end
end
