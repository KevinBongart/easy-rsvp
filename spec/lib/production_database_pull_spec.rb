require "spec_helper"
require "stringio"
require "tmpdir"
require_relative "../../lib/production_database_pull"

RSpec.describe ProductionDatabasePull do
  DatabaseConfig = Data.define(:adapter, :database, :host, :port, :username, :password)
  HashDatabaseConfig = Data.define(:adapter, :database, :host, :configuration_hash)

  class FakeCommandRunner
    attr_reader :calls
    attr_accessor :small_production_dump, :fail_production_restore

    def initialize
      @calls = []
    end

    def run!(*command, env: {})
      calls << { command: command.map(&:to_s), env: }
      executable = File.basename(command.first.to_s)

      if executable == "scp"
        File.binwrite(command.last, "production" * (small_production_dump ? 1 : 200))
      elsif executable == "pg_dump"
        file = command.find { |argument| argument.to_s.start_with?("--file=") }.to_s.delete_prefix("--file=")
        File.binwrite(file, "development" * 200)
      elsif executable == "pg_restore" && fail_production_restore && production_restore?(command)
        self.fail_production_restore = false
        raise ProductionDatabasePull::CommandError.new(command.map(&:to_s), "restore broke")
      end

      true
    end

    def run(*command, env: {})
      run!(*command, env:)
    rescue ProductionDatabasePull::CommandError
      false
    end

    private

    def production_restore?(command)
      command.none? { |argument| argument.to_s == "--list" } &&
        command.last.to_s.include?("easy-rsvp-production")
    end
  end

  let(:temporary_directory) { Pathname(Dir.mktmpdir) }
  let(:postgres_bin) { temporary_directory.join("postgres-bin") }
  let(:backup_dir) { temporary_directory.join("backups") }
  let(:runner) { FakeCommandRunner.new }
  let(:output) { StringIO.new }
  let(:disconnect) { instance_double(Proc, call: true) }
  let(:database_config) do
    DatabaseConfig.new(
      adapter: "postgresql",
      database: "events_development",
      host: nil,
      port: nil,
      username: nil,
      password: nil
    )
  end
  let(:environment) do
    {
      "DOKKU_PG_SERVICE" => "easy-rsvp-db",
      "DOKKU_HOST" => "root@example.test",
      "PG_BIN" => postgres_bin.to_s
    }
  end

  before do
    FileUtils.mkdir_p(postgres_bin)
    described_class::POSTGRES_EXECUTABLES.each do |executable|
      path = postgres_bin.join(executable)
      FileUtils.touch(path)
      FileUtils.chmod(0o700, path)
    end
  end

  after do
    FileUtils.remove_entry(temporary_directory) if temporary_directory.exist?
  end

  def pull(input: StringIO.new("events_development\n"), **overrides)
    described_class.new(
      database_config:,
      rails_environment: "development",
      rails_command: "/app/bin/rails",
      backup_dir:,
      disconnect:,
      env: environment,
      input:,
      output:,
      runner:,
      clock: class_double(Time, now: Time.utc(2026, 8, 21, 12)),
      process_id: 123,
      **overrides
    ).call
  end

  it "stages, copies, validates, and restores production after backing up development" do
    result = pull

    commands = runner.calls.map { |call| call.fetch(:command) }
    expect(commands[0]).to eq([
      "ssh", "root@example.test",
      "umask 077 && dokku postgres:export easy-rsvp-db > /tmp/easy-rsvp-production-20260821T120000Z-123.pgdump"
    ])
    expect(commands[1]).to eq([
      "scp", "--",
      "root@example.test:/tmp/easy-rsvp-production-20260821T120000Z-123.pgdump",
      result.production_dump.to_s
    ])
    expect(commands[2]).to eq([
      "ssh", "root@example.test",
      "rm -f -- /tmp/easy-rsvp-production-20260821T120000Z-123.pgdump"
    ])
    expect(commands.map { |command| File.basename(command.first) }).to include(
      "pg_dump", "pg_restore", "dropdb", "createdb", "rails"
    )
    expect(disconnect).to have_received(:call)
    expect(result.production_dump).to exist
    expect(result.development_backup).to exist
    expect(File.stat(result.production_dump).mode & 0o777).to eq(0o600)
  end

  it "does not run commands when confirmation is wrong" do
    expect { pull(input: StringIO.new("no\n")) }
      .to raise_error(described_class::Error, /Aborted/)
    expect(runner.calls).to be_empty
  end

  it "permits an exact noninteractive confirmation" do
    environment["CONFIRM_PULL_PRODUCTION"] = "events_development"

    expect { pull(input: StringIO.new) }.not_to raise_error
  end

  it "supports Rails database configs that expose connection settings through configuration_hash" do
    config = HashDatabaseConfig.new(
      adapter: "postgresql",
      database: "events_development",
      host: nil,
      configuration_hash: { port: 5432, username: "events", password: "secret" }
    )

    pull(database_config: config)

    postgres_call = runner.calls.find { |call| File.basename(call.fetch(:command).first) == "pg_dump" }
    expect(postgres_call.fetch(:env)).to include(
      "PGPORT" => "5432",
      "PGUSER" => "events",
      "PGPASSWORD" => "secret"
    )
  end

  it "refuses a non-development Rails environment" do
    expect { pull(rails_environment: "production") }
      .to raise_error(described_class::Error, /outside the development/)
    expect(runner.calls).to be_empty
  end

  it "refuses any database other than events_development" do
    config = database_config.with(database: "events_production")

    expect { pull(database_config: config) }
      .to raise_error(described_class::Error, /expected "events_development"/)
    expect(runner.calls).to be_empty
  end

  it "clears inherited PostgreSQL connection overrides for local commands" do
    pull

    postgres_calls = runner.calls.select do |call|
      described_class::POSTGRES_EXECUTABLES.include?(File.basename(call.fetch(:command).first))
    end
    expect(postgres_calls).not_to be_empty
    postgres_calls.each do |call|
      expect(call.fetch(:env)).to include(
        "PGHOST" => nil, "PGPORT" => nil, "PGUSER" => nil, "PGPASSWORD" => nil,
        "PGHOSTADDR" => nil, "PGSERVICE" => nil, "PGSERVICEFILE" => nil
      )
    end
  end

  it "rejects SSH options in place of a hostname" do
    environment["DOKKU_HOST"] = "-V"

    expect { pull }.to raise_error(described_class::Error, /DOKKU_HOST/)
    expect(runner.calls).to be_empty
  end

  it "refuses a development configuration pointed at a remote host" do
    remote_config = database_config.with(host: "database.example.test")

    expect { pull(database_config: remote_config) }
      .to raise_error(described_class::Error, /non-local database host/)
    expect(runner.calls).to be_empty
  end

  it "requires an explicit Dokku PostgreSQL service" do
    environment.delete("DOKKU_PG_SERVICE")

    expect { pull }.to raise_error(described_class::Error, /DOKKU_PG_SERVICE/)
    expect(runner.calls).to be_empty
  end

  it "does not touch development when the copied archive is invalid" do
    runner.small_production_dump = true

    expect { pull }.to raise_error(described_class::Error, /suspiciously small/)
    commands = runner.calls.map { |call| call.fetch(:command) }
    expect(commands.map { |command| File.basename(command.first) }).not_to include(
      "pg_dump", "dropdb", "createdb"
    )
    expect(commands).to include([
      "ssh", "root@example.test",
      "rm -f -- /tmp/easy-rsvp-production-20260821T120000Z-123.pgdump"
    ])
  end

  it "automatically restores the development backup after a restore failure" do
    runner.fail_production_restore = true

    expect { pull }.to raise_error(described_class::CommandError, /restore broke/)
    restore_calls = runner.calls.map { |call| call.fetch(:command) }.select do |command|
      File.basename(command.first) == "pg_restore" && !command.include?("--list")
    end
    expect(restore_calls.length).to eq(2)
    expect(restore_calls.last.last).to include("development-before")
    expect(output.string).to include("Previous development database restored")
  end
end
