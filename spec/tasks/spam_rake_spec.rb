require 'rails_helper'
require 'rake'

RSpec.describe 'spam:purge_images' do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?('spam:purge_images')
  end

  let(:task) { Rake::Task['spam:purge_images'] }

  after { task.reenable }

  it 'purges expired operator-spam images and prints a one-line summary' do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('x' * 42), filename: 'photo.png', content_type: 'image/png')
    event = create(:event, title: 'Private party at 12 Example Street')
    event.update!(body: %(<action-text-attachment sgid="#{blob.attachable_sgid}"></action-text-attachment>))
    event.update_columns(spam_at: 31.days.ago, spam_source: 'operator', spam_decided_at: 31.days.ago)

    expect { task.invoke }.to output("spam:purge_images events=1 purged_blobs=1 purged_bytes=42 kept_shared_blobs=0\n").to_stdout

    expect(ActiveStorage::Blob.exists?(blob.id)).to be(false)
  end

  it 'is scheduled daily by Dokku' do
    cron = JSON.parse(Rails.root.join('app.json').read).fetch('cron')

    expect(cron).to include(a_hash_including('command' => 'bin/rails spam:purge_images', 'schedule' => '17 4 * * *'))
  end
end
