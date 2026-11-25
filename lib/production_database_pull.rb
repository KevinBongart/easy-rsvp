# frozen_string_literal: true

require "fileutils"
require "open3"
require "pathname"
require "securerandom"
require "shellwords"
require "tmpdir"

# Copies a Dokku PostgreSQL export to this machine, either to replace only Easy
# RSVP's local development database or to keep as a GPG-encrypted backup. The
# production database is never written to.
class ProductionDatabasePull
  DEVELOPMENT_DATABASE = "events_development"
  LOCAL_DATABASE_HOSTS = [ nil, "", "localhost", "127.0.0.1", "::1" ].freeze
  MINIMUM_ARCHIVE_SIZE = 1_024
  POSTGRES_EXECUTABLES = %w[pg_dump pg_restore dropdb createdb].freeze
  # Basic ISO 8601 (no separators), so backup file names sort by time.
  TIMESTAMP_FORMAT = "%Y%m%dT%H%M%SZ"
  PLAINTEXT_DIRECTORY_PREFIX = "easy-rsvp-plaintext-"

  Result = Data.define(:production_dump, :development_backup)

  class Error < StandardError; end

  class CommandError < Error
    attr_reader :detail

    def initialize(command, stderr)
      @detail = stderr.to_s.strip
      message = "Command failed: #{Shellwords.join(command)}"
      message = "#{message}\n#{detail}" unless detail.empty?
      super(message)
    end
  end

  class CommandRunner
    def run!(*command, env: {})
      _stdout, stderr, status = Open3.capture3(env, *command.map(&:to_s))
      raise CommandError.new(command.map(&:to_s), stderr) unless status.success?

      true
    end

    def run(*command, env: {})
      run!(*command, env:)
    rescue CommandError
      false
    end
  end

  def initialize(
    database_config:,
    rails_environment:,
    rails_command:,
    backup_dir:,
    disconnect:,
    env: ENV,
    input: $stdin,
    output: $stdout,
    runner: CommandRunner.new,
    clock: Time,
    process_id: Process.pid,
    nonce_generator: SecureRandom
  )
    @database_config = database_config
    @rails_environment = rails_environment.to_s
    @rails_command = rails_command.to_s
    @backup_dir = Pathname(backup_dir)
    @disconnect = disconnect
    @env = env
    @input = input
    @output = output
    @runner = runner
    @clock = clock
    @process_id = process_id
    @nonce_generator = nonce_generator
  end

  def call
    validate_local_target!
    host, service = dokku_settings
    postgres_bin = resolve_postgres_bin
    confirm!

    prepare_backup_directory
    timestamp = clock.now.utc.strftime(TIMESTAMP_FORMAT)
    stem = "easy-rsvp-production-#{timestamp}-#{process_id}"
    production_dump = backup_dir.join("#{stem}.pgdump")
    development_backup = backup_dir.join("easy-rsvp-development-before-#{timestamp}-#{process_id}.pgdump")
    remote_dump = "/tmp/#{stem}.pgdump"

    copy_production_dump(host:, service:, remote_dump:, production_dump:)
    replace_development_database(production_dump, development_backup, postgres_bin:)

    output.puts "Development database refreshed successfully."
    output.puts "Production dump: #{production_dump}"
    output.puts "Previous development data: #{development_backup}"
    Result.new(production_dump:, development_backup:)
  end

  # Only the GPG-encrypted archive is published. The plaintext export exists
  # just long enough to be validated, in an owner-only directory removed even
  # when a step fails or the task is interrupted.
  def backup
    validate_local_target!
    host, service = dokku_settings
    recipient = backup_recipient
    postgres_bin = resolve_postgres_bin(required_executables: %w[pg_restore])

    prepare_backup_directory
    timestamp = clock.now.utc.strftime(TIMESTAMP_FORMAT)
    filename = "easy-rsvp-production-#{timestamp}.pgdump.gpg"
    encrypted_backup = backup_dir.join(filename)
    partial_backup = backup_dir.join(".#{filename}.partial")
    reserve_archive!(partial_backup, encrypted_backup)
    reserved_partial = true
    remote_dump = "/tmp/easy-rsvp-production-#{timestamp}-#{process_id}-#{nonce_generator.hex(4)}.pgdump"

    Dir.mktmpdir(PLAINTEXT_DIRECTORY_PREFIX, backup_dir) do |plaintext_directory|
      production_dump = Pathname(plaintext_directory).join("production.pgdump")
      copy_production_dump(host:, service:, remote_dump:, production_dump:)
      validate_archive!(production_dump, postgres_bin:)
      encrypt!(production_dump, partial_backup, recipient:)
    end
    publish_archive!(partial_backup, encrypted_backup)

    output.puts "Encrypted production backup downloaded and read successfully: #{encrypted_backup}"
    encrypted_backup
  ensure
    FileUtils.rm_f(partial_backup) if reserved_partial
  end

  def restore_backup(encrypted_backup)
    validate_local_target!
    encrypted_backup = Pathname(encrypted_backup)
    raise Error, "No backup found at #{encrypted_backup}." unless encrypted_backup.file?

    postgres_bin = resolve_postgres_bin
    confirm!

    prepare_backup_directory
    timestamp = clock.now.utc.strftime(TIMESTAMP_FORMAT)
    development_backup = backup_dir.join("easy-rsvp-development-before-#{timestamp}-#{process_id}.pgdump")

    Dir.mktmpdir(PLAINTEXT_DIRECTORY_PREFIX, backup_dir) do |plaintext_directory|
      production_dump = Pathname(plaintext_directory).join("production.pgdump")
      output.puts "Decrypting #{encrypted_backup}..."
      runner.run!("gpg", "--decrypt", "--output", production_dump, "--", encrypted_backup)
      replace_development_database(production_dump, development_backup, postgres_bin:)
    end

    output.puts "Development database restored from #{encrypted_backup}."
    output.puts "Previous development data: #{development_backup}"
    development_backup
  end

  private

  attr_reader :database_config, :rails_environment, :rails_command, :backup_dir,
              :disconnect, :env, :input, :output, :runner, :clock, :process_id,
              :nonce_generator

  def validate_local_target!
    unless rails_environment == "development"
      raise Error, "Refusing to replace a database outside the development Rails environment."
    end
    unless database_config.adapter == "postgresql"
      raise Error, "Expected PostgreSQL, found #{database_config.adapter.inspect}."
    end
    unless database_config.database == DEVELOPMENT_DATABASE
      raise Error, "Refusing to replace database #{database_config.database.inspect}; expected #{DEVELOPMENT_DATABASE.inspect}."
    end
    unless LOCAL_DATABASE_HOSTS.include?(database_config.host)
      raise Error, "Refusing to replace a non-local database host: #{database_config.host.inspect}."
    end
  end

  def required_setting(name)
    value = env[name].to_s.strip
    raise Error, "Set #{name} before accessing the production database." if value.empty?

    value
  end

  def dokku_settings
    service = required_setting("DOKKU_PG_SERVICE")
    host = required_setting("DOKKU_HOST")
    validate_remote_setting!(host, service)
    [ host, service ]
  end

  # A test encryption, run before the server is contacted, so a typo or an
  # expired, revoked or untrusted key cannot leave a production export that has
  # nowhere safe to go. `--list-keys` would accept all of those.
  def backup_recipient
    recipient = required_setting("BACKUP_GPG_RECIPIENT")
    unless runner.run(
      "gpg", "--batch", "--yes", "--auto-key-locate", "local", "--encrypt", "--recipient", recipient,
      "--output", File::NULL, "--", File::NULL
    )
      raise Error, "BACKUP_GPG_RECIPIENT is not a usable encryption key in your GPG keyring " \
        "(missing, expired, revoked or untrusted)."
    end

    recipient
  end

  def validate_remote_setting!(host, service)
    unless host.match?(/\A(?:[a-zA-Z0-9_][a-zA-Z0-9_.-]*@)?[a-zA-Z0-9_][a-zA-Z0-9_.-]*\z/)
      raise Error, "DOKKU_HOST contains unsupported characters."
    end
    unless service.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_-]*\z/)
      raise Error, "DOKKU_PG_SERVICE contains unsupported characters."
    end
  end

  def confirm!
    supplied_confirmation = env["CONFIRM_PULL_PRODUCTION"].to_s
    return if supplied_confirmation == DEVELOPMENT_DATABASE

    output.puts "This will replace local #{DEVELOPMENT_DATABASE} with production data."
    output.print "Type #{DEVELOPMENT_DATABASE} to continue: "
    answer = input.gets.to_s.strip
    raise Error, "Aborted without changing either database." unless answer == DEVELOPMENT_DATABASE
  end

  def prepare_backup_directory
    FileUtils.mkdir_p(backup_dir, mode: 0o700)
    FileUtils.chmod(0o700, backup_dir)
  end

  def copy_production_dump(host:, service:, remote_dump:, production_dump:)
    export = "umask 077 && #{Shellwords.join([ "dokku", "postgres:export", service ])} > #{Shellwords.escape(remote_dump)}"
    cleanup = Shellwords.join([ "rm", "-f", "--", remote_dump ])

    output.puts "Creating a temporary production export on #{host}..."
    primary_error = nil
    begin
      runner.run!("ssh", host, export)
      output.puts "Copying the export to #{production_dump}..."
      runner.run!("scp", "--", "#{host}:#{remote_dump}", production_dump.to_s)
      FileUtils.chmod(0o600, production_dump)
    rescue StandardError => error
      primary_error = error
      raise
    ensure
      cleaned = runner.run("ssh", host, cleanup)
      unless cleaned
        message = "Could not remove production export #{remote_dump} from #{host}; remove it manually."
        primary_error ? output.puts("Warning: #{message}") : raise(Error, message)
      end
    end
  end

  def publish_archive!(partial_dump, production_dump)
    File.link(partial_dump, production_dump)
    FileUtils.rm_f(partial_dump)
  rescue Errno::EEXIST
    raise Error, "Refusing to overwrite existing backup: #{production_dump}"
  end

  def reserve_archive!(partial_dump, production_dump)
    raise Error, "Refusing to overwrite existing backup: #{production_dump}" if production_dump.exist?

    File.open(partial_dump, File::WRONLY | File::CREAT | File::EXCL, 0o600) { }
  rescue Errno::EEXIST
    raise Error, "Another backup is already using #{partial_dump}"
  end

  def encrypt!(production_dump, encrypted_backup, recipient:)
    output.puts "Encrypting the export to #{encrypted_backup}..."
    # --yes overwrites the empty partial file reserve_archive! created.
    runner.run!(
      "gpg", "--batch", "--yes", "--encrypt", "--recipient", recipient,
      "--output", encrypted_backup, "--", production_dump
    )
    FileUtils.chmod(0o600, encrypted_backup)
  rescue CommandError => error
    # Re-raised without the command line, which names the recipient.
    raise Error, "GPG could not encrypt the export.\n#{error.detail}".strip
  end

  def replace_development_database(production_dump, development_backup, postgres_bin:)
    validate_archive!(production_dump, postgres_bin:)
    backup_development_database(development_backup, postgres_bin:)
    validate_archive!(development_backup, postgres_bin:)

    disconnect.call
    replace_started = true
    replace_database(production_dump, postgres_bin:)
    set_development_environment!
  rescue StandardError
    restore_development_backup(development_backup, postgres_bin:) if replace_started
    raise
  end

  def backup_development_database(file, postgres_bin:)
    output.puts "Backing up current #{DEVELOPMENT_DATABASE} to #{file}..."
    runner.run!(
      postgres_bin.join("pg_dump"),
      "--format=custom",
      "--no-owner",
      "--no-acl",
      "--file=#{file}",
      DEVELOPMENT_DATABASE,
      env: postgres_environment
    )
    FileUtils.chmod(0o600, file)
  end

  def validate_archive!(file, postgres_bin:)
    size = File.size?(file) || 0
    if size < MINIMUM_ARCHIVE_SIZE
      raise Error, "Archive #{file} is suspiciously small (#{size} bytes); local data was not changed."
    end

    runner.run!(postgres_bin.join("pg_restore"), "--list", file, env: archive_environment)
    runner.run!(postgres_bin.join("pg_restore"), "--file=#{File::NULL}", file, env: archive_environment)
  end

  def replace_database(archive, postgres_bin:)
    output.puts "Replacing #{DEVELOPMENT_DATABASE}..."
    recreate_database(postgres_bin:)
    runner.run!(
      postgres_bin.join("pg_restore"),
      "--no-owner",
      "--no-acl",
      "--clean",
      "--if-exists",
      "--dbname=#{DEVELOPMENT_DATABASE}",
      archive,
      env: postgres_environment
    )
  end

  def restore_development_backup(file, postgres_bin:)
    output.puts "Restore failed; putting the previous development database back..."
    recreate_database(postgres_bin:)
    runner.run!(
      postgres_bin.join("pg_restore"),
      "--no-owner",
      "--no-acl",
      "--dbname=#{DEVELOPMENT_DATABASE}",
      file,
      env: postgres_environment
    )
    set_development_environment!
    output.puts "Previous development database restored from #{file}."
  rescue StandardError => rollback_error
    raise Error, "The production restore failed and the automatic rollback also failed: #{rollback_error.message}. " \
      "The previous development archive remains at #{file}."
  end

  def recreate_database(postgres_bin:)
    runner.run!(
      postgres_bin.join("dropdb"), "--if-exists", DEVELOPMENT_DATABASE,
      env: postgres_environment
    )
    runner.run!(postgres_bin.join("createdb"), DEVELOPMENT_DATABASE, env: postgres_environment)
  end

  def set_development_environment!
    runner.run!(
      rails_command,
      "db:environment:set",
      env: { "RAILS_ENV" => "development" }
    )
  end

  def postgres_environment
    # Nil values unset inherited libpq settings so the shell cannot redirect a
    # validated local configuration to another server or connection service.
    {
      "PGHOST" => database_setting(:host),
      "PGPORT" => database_setting(:port),
      "PGUSER" => database_setting(:username),
      "PGPASSWORD" => database_setting(:password),
      "PGHOSTADDR" => nil,
      "PGSERVICE" => nil,
      "PGSERVICEFILE" => nil
    }.transform_values { |value| value&.to_s }
  end

  def archive_environment
    {
      "PGHOST" => nil,
      "PGPORT" => nil,
      "PGUSER" => nil,
      "PGPASSWORD" => nil,
      "PGDATABASE" => nil,
      "PGHOSTADDR" => nil,
      "PGSERVICE" => nil,
      "PGSERVICEFILE" => nil,
      "PGPASSFILE" => nil
    }
  end

  def database_setting(name)
    return database_config.public_send(name) if database_config.respond_to?(name)
    return unless database_config.respond_to?(:configuration_hash)

    database_config.configuration_hash[name]
  end

  def resolve_postgres_bin(required_executables: POSTGRES_EXECUTABLES)
    candidates = []
    candidates << env["PG_BIN"] unless env["PG_BIN"].to_s.empty?
    candidates.concat([
      "/opt/homebrew/opt/postgresql/bin",
      "/usr/local/opt/postgresql/bin"
    ])
    candidates.concat(Dir["/usr/lib/postgresql/*/bin"].sort.reverse)
    candidates.concat(env.fetch("PATH", "").split(File::PATH_SEPARATOR))

    directory = candidates.compact.map { |candidate| Pathname(candidate) }.find do |candidate|
      required_executables.all? { |executable| File.executable?(candidate.join(executable)) }
    end
    return directory if directory

    raise Error, "Could not find #{required_executables.join(', ')} in one directory. Set PG_BIN."
  end
end
