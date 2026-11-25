require 'rails_helper'
require 'rake'

RSpec.describe 'images:purge' do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?('images:purge')
  end

  let(:task) { Rake::Task['images:purge'] }

  after { task.reenable }

  def upload
    travel_to(3.days.ago) do
      ActiveStorage::Blob.create_and_upload!(io: StringIO.new('x' * 42), filename: 'photo.png', content_type: 'image/png')
    end
  end

  it 'purges expired operator-spam images, printing one line per blob and a summary' do
    blob = upload
    event = create(:event, title: 'Private party at 12 Example Street')
    event.update!(body: %(<action-text-attachment sgid="#{blob.attachable_sgid}"></action-text-attachment>))
    event.update_columns(spam_at: 31.days.ago, spam_source: :operator, spam_decided_at: 31.days.ago)

    expect { task.invoke }.to output(
      "images:purge deleted blob_id=#{blob.id} key=#{blob.key} byte_size=42 reason=operator_spam\n" \
      "images:purge operator_spam=1 automatic_spam=0 unattached_upload=0 unreferenced_legacy_upload=0 " \
      "deleted_bytes=42 kept_shared_blobs=0 failed_deletes=0 limit_reached=false\n"
    ).to_stdout

    expect(ActiveStorage::Blob.exists?(blob.id)).to be(false)
  end

  it 'only lists what it would delete with DRY_RUN=1' do
    blob = upload
    stub_const('ENV', ENV.to_h.merge('DRY_RUN' => '1'))

    expect { task.invoke }.to output(/would delete blob_id=#{blob.id} .*\nimages:purge dry_run .*unattached_upload=1/).to_stdout

    expect(ActiveStorage::Blob.exists?(blob.id)).to be(true)
  end

  it 'deletes when DRY_RUN is 0' do
    blob = upload
    stub_const('ENV', ENV.to_h.merge('DRY_RUN' => '0'))

    expect { task.invoke }.to output(/images:purge deleted blob_id=#{blob.id} /).to_stdout
    expect(ActiveStorage::Blob.exists?(blob.id)).to be(false)
  end

  it 'exits non-zero when a stored file could not be deleted' do
    result = ImageCleanup::Result.new(dry_run: false, deleted_blobs: {}, deleted_bytes: 0, kept_shared_blobs: 0, failed_deletes: 1, limit_reached: false)
    allow(ImageCleanup).to receive(:run).and_return(result)

    expect { task.invoke }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      .and output(/failed_deletes=1/).to_stdout
  end

  it 'is scheduled daily by Dokku, one run at a time' do
    cron = JSON.parse(Rails.root.join('app.json').read).fetch('cron')

    expect(cron).to eq([ { 'command' => 'bin/rails images:purge', 'schedule' => '17 4 * * *', 'concurrency_policy' => 'forbid' } ])
  end
end
