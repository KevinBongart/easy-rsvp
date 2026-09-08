require 'spec_helper'
require 'rbconfig'
require_relative '../../lib/production_database_pull'

RSpec.describe ProductionDatabasePull::CommandRunner do
  subject(:runner) { described_class.new }

  it 'executes a successful local command with explicit environment values' do
    expect(runner.run!(RbConfig.ruby, '-e', 'exit ENV.fetch("PULL_SPEC_VALUE") == "literal $value" ? 0 : 1', env: { 'PULL_SPEC_VALUE' => 'literal $value' })).to be(true)
  end

  it 'passes arguments literally rather than evaluating shell syntax' do
    expect(runner.run!(RbConfig.ruby, '-e', 'exit ARGV == ["$(exit 1); false"] ? 0 : 1', '$(exit 1); false')).to be(true)
  end

  it 'includes stderr in an actionable error for a failed command' do
    expect { runner.run!(RbConfig.ruby, '-e', 'warn "synthetic failure"; exit 7') }.to raise_error(ProductionDatabasePull::CommandError, /synthetic failure/)
  end

  it 'returns false for a failed best-effort cleanup command' do
    expect(runner.run(RbConfig.ruby, '-e', 'exit 7')).to be(false)
  end
end
