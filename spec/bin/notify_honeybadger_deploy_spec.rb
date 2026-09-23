require 'spec_helper'
require 'json'
require 'open3'
require 'tmpdir'

RSpec.describe 'bin/notify_honeybadger_deploy' do
  subject(:run_notifier) { Open3.capture3(environment, notifier_path) }

  let(:repository_root) { File.expand_path('../..', __dir__) }
  let(:notifier_path) { File.join(repository_root, 'bin/notify_honeybadger_deploy') }
  let(:environment) do
    {
      'HONEYBADGER_API_KEY' => nil,
      'GIT_REV' => nil
    }
  end

  it 'is registered as Dokku’s postdeploy task' do
    app_json = JSON.parse(File.read(File.join(repository_root, 'app.json')))

    expect(app_json.dig('scripts', 'dokku', 'postdeploy')).to eq('bin/notify_honeybadger_deploy')
  end

  it 'requires the Rails health endpoint to pass before Dokku switches traffic' do
    app_json = JSON.parse(File.read(File.join(repository_root, 'app.json')))

    expect(app_json.dig('healthchecks', 'web')).to contain_exactly(
      include(
        'type' => 'startup',
        'path' => '/up',
        'attempts' => 3
      )
    )
  end

  it 'fails clearly when Honeybadger is not configured' do
    _stdout, stderr, status = run_notifier

    expect(status).not_to be_success
    expect(stderr).to include('HONEYBADGER_API_KEY must be configured')
  end

  it 'fails clearly when Dokku does not provide a revision' do
    environment['HONEYBADGER_API_KEY'] = 'test-api-key'

    _stdout, stderr, status = run_notifier

    expect(status).not_to be_success
    expect(stderr).to include('GIT_REV must contain the deployed revision')
  end

  it 'loads the real CLI and configuration without booting Rails or using the network' do
    environment.merge!(
      'HONEYBADGER_API_KEY' => 'test-api-key',
      'GIT_REV' => 'abc123',
      'HONEYBADGER_BACKEND' => 'debug'
    )

    stdout, stderr, status = run_notifier

    expect(status).to be_success
    expect(stderr).to be_empty
    expect(stdout).to include('Skipping Rails initialization.', 'Deploy notification complete.')
  end

  context 'with a Honeybadger key and Dokku revision' do
    around do |example|
      Dir.mktmpdir do |directory|
        @directory = directory
        @argument_log = File.join(directory, 'arguments')
        fake_bundle_path = File.join(directory, 'bundle')
        File.write(fake_bundle_path, <<~SH)
          #!/usr/bin/env bash
          printf '%s\n' "$@" > "$DEPLOY_ARGUMENT_LOG"
          exit "${FAKE_BUNDLE_EXIT_STATUS:-0}"
        SH
        File.chmod(0o755, fake_bundle_path)
        example.run
      end
    end

    let(:environment) do
      {
        'PATH' => "#{@directory}:#{ENV.fetch('PATH')}",
        'DEPLOY_ARGUMENT_LOG' => @argument_log,
        'HONEYBADGER_API_KEY' => 'test-api-key',
        'GIT_REV' => 'abc123'
      }
    end

    it 'reports the deployed revision through the Honeybadger CLI' do
      _stdout, stderr, status = run_notifier

      expect(status).to be_success
      expect(stderr).to be_empty
      expect(File.readlines(@argument_log, chomp: true)).to eq(
        [
          'exec',
          'honeybadger',
          'deploy',
          '--skip-rails-load',
          '--repository=https://github.com/KevinBongart/easy-rsvp',
          '--revision=abc123',
          '--environment=production',
          '--user=dokku'
        ]
      )
    end

    it 'propagates a Honeybadger notification failure' do
      environment['FAKE_BUNDLE_EXIT_STATUS'] = '1'

      _stdout, _stderr, status = run_notifier

      expect(status).not_to be_success
    end
  end
end
