# frozen_string_literal: true

require "fileutils"
require "open3"
require "pathname"
require "shellwords"

# Copies a Dokku PostgreSQL export to this machine and replaces only Easy RSVP's
# local development database. The production database is never written to.
class ProductionDatabasePull
  DEVELOPMENT_DATABASE = "events_development"
  LOCAL_DATABASE_HOSTS = [ nil, "", "localhost", "127.0.0.1", "::1" ].freeze
  MINIMUM_ARCHIVE_SIZE = 1_024
  POSTGRES_EXECUTABLES = %w[pg_dump pg_restore dropdb createdb].freeze

  Result = Data.define(:production_dump, :development_backup)

  class Error < StandardError; end

  class CommandError < Error
    def initialize(command, stderr)
      detail = stderr.to_s.strip
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
    process_id: Process.pid
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
  end

  def call
    validate_local_target!
    service = required_setting("DOKKU_PG_SERVICE")
    host = required_setting("DOKKU_HOST")
    validate_remote_setting!(host, service)
    postgres_bin = resolve_postgres_bin
    confirm!

    prepare_backup_directory
    timestamp = clock.now.utc.strftime("%Y%m%dT%H%M%SZ")
    stem = "easy-rsvp-production-#{timestamp}-#{process_id}"
    production_dump = backup_dir.join("#{stem}.pgdump")
    development_backup = backup_dir.join("easy-rsvp-development-before-#{timestamp}-#{process_id}.pgdump")
    remote_dump = "/tmp/#{stem}.pgdump"

    copy_production_dump(host:, service:, remote_dump:, production_dump:)
    validate_archive!(production_dump, postgres_bin:)
    backup_development_database(development_backup, postgres_bin:)
    validate_archive!(development_backup, postgres_bin:)

    disconnect.call
    replace_started = true
    replace_database(production_dump, postgres_bin:)
    set_development_environment!

    output.puts "Development database refreshed successfully."
    output.puts "Production dump: #{production_dump}"
    output.puts "Previous development data: #{development_backup}"
    Result.new(production_dump:, development_backup:)
  rescue StandardError => error
    restore_development_backup(development_backup, postgres_bin:) if replace_started
    raise error
  end

  private

  attr_reader :database_config, :rails_environment, :rails_command, :backup_dir,
              :disconnect, :env, :input, :output, :runner, :clock, :process_id

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
    raise Error, "Set #{name} before importing the production database." if value.empty?

    value
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
    begin
      runner.run!("ssh", host, export)
      output.puts "Copying the export to #{production_dump}..."
      runner.run!("scp", "--", "#{host}:#{remote_dump}", production_dump.to_s)
      FileUtils.chmod(0o600, production_dump)
    ensure
      cleaned = runner.run("ssh", host, cleanup)
      output.puts "Warning: could not remove #{remote_dump} from #{host}." unless cleaned
    end
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

    runner.run!(postgres_bin.join("pg_restore"), "--list", file, env: postgres_environment)
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

  def database_setting(name)
    return database_config.public_send(name) if database_config.respond_to?(name)
    return unless database_config.respond_to?(:configuration_hash)

    database_config.configuration_hash[name]
  end

  def resolve_postgres_bin
    candidates = []
    candidates << env["PG_BIN"] unless env["PG_BIN"].to_s.empty?
    candidates.concat([
      "/opt/homebrew/opt/postgresql/bin",
      "/usr/local/opt/postgresql/bin"
    ])
    candidates.concat(Dir["/usr/lib/postgresql/*/bin"].sort.reverse)
    candidates.concat(env.fetch("PATH", "").split(File::PATH_SEPARATOR))

    directory = candidates.compact.map { |candidate| Pathname(candidate) }.find do |candidate|
      POSTGRES_EXECUTABLES.all? { |executable| File.executable?(candidate.join(executable)) }
    end
    return directory if directory

    raise Error, "Could not find pg_dump, pg_restore, dropdb, and createdb in one directory. Set PG_BIN."
  end
end
