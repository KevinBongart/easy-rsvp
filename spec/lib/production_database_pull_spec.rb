require "spec_helper"
require "stringio"
require "tmpdir"
require_relative "../../lib/production_database_pull"

RSpec.describe ProductionDatabasePull do
  DatabaseConfig = Data.define(:adapter, :database, :host, :port, :username, :password)
  HashDatabaseConfig = Data.define(:adapter, :database, :host, :configuration_hash)

  class FakeCommandRunner
    attr_reader :calls
    attr_accessor :small_production_dump, :fail_archive_read, :fail_copy,
      :fail_production_restore, :fail_remote_cleanup, :missing_gpg_key, :fail_encryption,
      :copied_dumps

    def initialize
      @calls = []
      @copied_dumps = []
    end

    def run!(*command, env: {})
      calls << { command: command.map(&:to_s), env: }
      executable = File.basename(command.first.to_s)

      if executable == "scp"
        raise ProductionDatabasePull::CommandError.new(command.map(&:to_s), "copy broke") if fail_copy

        File.binwrite(command.last, "production" * (small_production_dump ? 1 : 200))
        copied_dumps << Pathname(command.last)
      elsif executable == "gpg"
        run_gpg(command.map(&:to_s))
      elsif executable == "pg_dump"
        file = command.find { |argument| argument.to_s.start_with?("--file=") }.to_s.delete_prefix("--file=")
        File.binwrite(file, "development" * 200)
      elsif executable == "pg_restore" && fail_production_restore && production_restore?(command)
        self.fail_production_restore = false
        raise ProductionDatabasePull::CommandError.new(command.map(&:to_s), "restore broke")
      elsif executable == "pg_restore" && fail_archive_read &&
          command.any? { |argument| argument.to_s.start_with?("--file=") }
        raise ProductionDatabasePull::CommandError.new(command.map(&:to_s), "archive read broke")
      end

      true
    end

    def run(*command, env: {})
      if fail_remote_cleanup && command.first.to_s == "ssh" && command.last.to_s.start_with?("rm -f -- ")
        calls << { command: command.map(&:to_s), env: }
        return false
      end

      run!(*command, env:)
    rescue ProductionDatabasePull::CommandError
      false
    end

    private

    def run_gpg(command)
      if command.include?("--encrypt") && command.last == File::NULL
        raise ProductionDatabasePull::CommandError.new(command, "no public key") if missing_gpg_key
      elsif command.include?("--encrypt")
        raise ProductionDatabasePull::CommandError.new(command, "encryption broke") if fail_encryption

        File.binwrite(output_argument(command), "encrypted")
      elsif command.include?("--decrypt")
        File.binwrite(output_argument(command), "production" * 200)
      end
    end

    def output_argument(command)
      command[command.index("--output") + 1]
    end

    def production_restore?(command)
      command.any? { |argument| argument.to_s.start_with?("--dbname=") } &&
        !command.last.to_s.include?("development-before")
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
      "BACKUP_GPG_RECIPIENT" => "backups@example.test",
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
    database_pull(input:, **overrides).call
  end

  def backup(**overrides)
    database_pull(**overrides).backup
  end

  def restore_backup(file, input: StringIO.new("events_development\n"), **overrides)
    database_pull(input:, **overrides).restore_backup(file)
  end

  def database_pull(input: StringIO.new, **overrides)
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
      nonce_generator: class_double(SecureRandom, hex: "a1b2c3d4"),
      **overrides
    )
  end

  def leftover_backup_files
    backup_dir.children.reject { |path| path.extname == ".gpg" }
  end

  it "creates, validates, and encrypts a timestamped production backup without changing either database" do
    filename = "easy-rsvp-production-20260821T120000Z.pgdump.gpg"
    remote_filename = "easy-rsvp-production-20260821T120000Z-123-a1b2c3d4.pgdump"
    partial = backup_dir.join(".#{filename}.partial")
    expected = backup_dir.join(filename)
    result = backup

    expect(result).to eq(expected)
    expect(File.binread(result)).to eq("encrypted")
    expect(File.stat(result).mode & 0o777).to eq(0o600)
    expect(backup_dir.children).to eq([ expected ])

    expect(runner.copied_dumps.length).to eq(1)
    plaintext = runner.copied_dumps.first
    expect(plaintext.dirname.basename.to_s).to start_with("easy-rsvp-plaintext-")
    expect(plaintext.dirname.dirname).to eq(backup_dir)

    commands = runner.calls.map { |call| call.fetch(:command) }
    expect(commands[0]).to eq([
      "gpg", "--batch", "--yes", "--auto-key-locate", "local", "--encrypt", "--recipient", "backups@example.test",
      "--output", File::NULL, "--", File::NULL
    ])
    expect(commands[1]).to eq([
      "ssh", "root@example.test",
      "umask 077 && dokku postgres:export easy-rsvp-db > /tmp/#{remote_filename}"
    ])
    expect(commands[2]).to eq([
      "scp", "--",
      "root@example.test:/tmp/#{remote_filename}",
      plaintext.to_s
    ])
    expect(commands[3]).to eq([
      "ssh", "root@example.test",
      "rm -f -- /tmp/#{remote_filename}"
    ])
    expect(commands[4]).to eq([
      postgres_bin.join("pg_restore").to_s,
      "--list",
      plaintext.to_s
    ])
    expect(commands[5]).to eq([
      postgres_bin.join("pg_restore").to_s,
      "--file=#{File::NULL}",
      plaintext.to_s
    ])
    expect(commands[6]).to eq([
      "gpg", "--batch", "--yes", "--encrypt", "--recipient", "backups@example.test",
      "--output", partial.to_s, "--", plaintext.to_s
    ])
    expect(runner.calls[4].fetch(:env)).to include("PGPASSWORD" => nil, "PGDATABASE" => nil)
    expect(runner.calls[5].fetch(:env)).to include("PGPASSWORD" => nil, "PGDATABASE" => nil)
    expect(commands.map { |command| File.basename(command.first) }).not_to include(
      "pg_dump", "dropdb", "createdb", "rails"
    )
    expect(disconnect).not_to have_received(:call)
  end

  it "requires a GPG recipient before contacting the server" do
    environment.delete("BACKUP_GPG_RECIPIENT")

    expect { backup }.to raise_error(described_class::Error, /Set BACKUP_GPG_RECIPIENT/)
    expect(runner.calls).to be_empty
  end

  it "requires the GPG recipient's public key before contacting the server" do
    runner.missing_gpg_key = true

    expect { backup }.to raise_error(described_class::Error) { |error|
      expect(error.message).to include("BACKUP_GPG_RECIPIENT is not a usable encryption key")
      expect(error.message).not_to include("backups@example.test")
    }
    expect(runner.calls.map { |call| call.fetch(:command).first }).to eq([ "gpg" ])
    expect(backup_dir).not_to exist
  end

  it "leaves no plaintext or partial file when encryption fails" do
    runner.fail_encryption = true

    expect { backup }.to raise_error(described_class::Error) { |error|
      expect(error).not_to be_a(described_class::CommandError)
      expect(error.message).to include("GPG could not encrypt the export.", "encryption broke")
      expect(error.message).not_to include("backups@example.test")
    }
    expect(backup_dir.children).to be_empty
    expect(runner.calls.map { |call| call.fetch(:command) }).to include([
      "ssh", "root@example.test",
      "rm -f -- /tmp/easy-rsvp-production-20260821T120000Z-123-a1b2c3d4.pgdump"
    ])
  end

  it "leaves no plaintext or partial file when interrupted" do
    allow(runner).to receive(:run!).and_wrap_original do |original, *command, **options|
      raise Interrupt if command.first == "gpg" && command.include?("--encrypt") && command.last != File::NULL

      original.call(*command, **options)
    end

    expect { backup }.to raise_error(Interrupt)
    expect(backup_dir.children).to be_empty
  end

  it "does not publish an invalid production backup" do
    runner.small_production_dump = true

    expect { backup }.to raise_error(described_class::Error, /suspiciously small/)
    expect(backup_dir.children).to be_empty
  end

  it "fails and removes local files when the remote export cannot be removed" do
    runner.fail_remote_cleanup = true

    expect { backup }.to raise_error(described_class::Error, %r{remove production export /tmp/})
    expect(backup_dir.children).to be_empty
  end

  it "preserves a copy error when remote cleanup also fails" do
    runner.fail_copy = true
    runner.fail_remote_cleanup = true

    expect { backup }.to raise_error(described_class::CommandError, /copy broke/)
    expect(output.string).to match(%r{Warning: Could not remove production export /tmp/})
  end

  it "does not publish an archive that cannot be read completely" do
    runner.fail_archive_read = true

    expect { backup }.to raise_error(described_class::CommandError, /archive read broke/)
    expect(backup_dir.children).to be_empty
  end

  it "refuses to overwrite a backup from the same timestamp" do
    first = backup
    runner.calls.clear

    expect { backup }.to raise_error(described_class::Error, /existing backup/)
    expect(first.basename.to_s).to eq("easy-rsvp-production-20260821T120000Z.pgdump.gpg")
    expect(runner.calls.map { |call| call.fetch(:command).first }).to eq([ "gpg" ])
  end

  it "does not delete a partial file reserved by another backup" do
    FileUtils.mkdir_p(backup_dir)
    partial = backup_dir.join(".easy-rsvp-production-20260821T120000Z.pgdump.gpg.partial")
    File.binwrite(partial, "another backup is writing here")

    expect { backup }.to raise_error(described_class::Error, /Another backup/)
    expect(File.binread(partial)).to eq("another backup is writing here")
    expect(runner.calls.map { |call| call.fetch(:command).first }).to eq([ "gpg" ])
  end

  describe "restoring an encrypted backup" do
    let(:encrypted_backup) { temporary_directory.join("easy-rsvp-production-20260820T120000Z.pgdump.gpg") }

    before { File.binwrite(encrypted_backup, "encrypted") }

    it "decrypts into a removed owner-only directory and replaces development after backing it up" do
      result = restore_backup(encrypted_backup)

      commands = runner.calls.map { |call| call.fetch(:command) }
      decrypt = commands.first
      plaintext = decrypt[decrypt.index("--output") + 1]
      expect(decrypt).to eq([ "gpg", "--decrypt", "--output", plaintext, "--", encrypted_backup.to_s ])
      expect(Pathname(plaintext).dirname.basename.to_s).to start_with("easy-rsvp-plaintext-")
      expect(commands).to include(a_collection_including("--dbname=events_development", plaintext))
      expect(commands.map { |command| File.basename(command.first) }).not_to include("ssh", "scp")
      expect(disconnect).to have_received(:call)
      expect(result).to eq(backup_dir.join("easy-rsvp-development-before-20260821T120000Z-123.pgdump"))
      expect(backup_dir.children).to eq([ result ])
    end

    it "puts development back and removes the plaintext when the restore fails" do
      runner.fail_production_restore = true

      expect { restore_backup(encrypted_backup) }.to raise_error(described_class::CommandError, /restore broke/)
      expect(output.string).to include("Previous development database restored")
      expect(leftover_backup_files.map { |path| path.basename.to_s })
        .to eq([ "easy-rsvp-development-before-20260821T120000Z-123.pgdump" ])
    end

    it "does not run commands when confirmation is wrong" do
      expect { restore_backup(encrypted_backup, input: StringIO.new("no\n")) }
        .to raise_error(described_class::Error, /Aborted/)
      expect(runner.calls).to be_empty
    end

    it "reports a missing backup file" do
      expect { restore_backup(temporary_directory.join("missing.pgdump.gpg")) }
        .to raise_error(described_class::Error, /No backup found/)
      expect(runner.calls).to be_empty
    end
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

  [ nil, "", "   " ].each do |host|
    it "rejects a missing or blank Dokku host (#{host.inspect}) before running commands" do
      host.nil? ? environment.delete("DOKKU_HOST") : environment["DOKKU_HOST"] = host

      expect { pull }.to raise_error(described_class::Error, /Set DOKKU_HOST/)
      expect(runner.calls).to be_empty
      expect(disconnect).not_to have_received(:call)
      expect(backup_dir).not_to exist
    end
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
      File.basename(command.first) == "pg_restore" &&
        command.any? { |argument| argument.start_with?("--dbname=") }
    end
    expect(restore_calls.length).to eq(2)
    expect(restore_calls.last.last).to include("development-before")
    expect(output.string).to include("Previous development database restored")
  end
end
