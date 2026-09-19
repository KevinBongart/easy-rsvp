require 'rails_helper'
require 'fileutils'
require 'open3'
require 'tmpdir'

RSpec.describe 'bin/docs-only-changes' do
  let(:script) { Rails.root.join('bin/docs-only-changes').to_s }

  around do |example|
    Dir.mktmpdir('docs-only-changes-spec') do |directory|
      @repository = directory
      git('init', '--quiet')
      git('config', 'user.email', 'spec@example.test')
      git('config', 'user.name', 'Spec User')
      write_and_commit('app.rb', "puts 'baseline'\n")
      @base_revision = git('rev-parse', 'HEAD').strip
      example.run
    end
  end

  it 'accepts Markdown and documentation-directory changes' do
    write_and_commit('README.md', "# Documentation\n")
    write_and_commit('docs/diagram.svg', '<svg></svg>')

    expect(docs_only?).to be(true)
  end

  it 'rejects changes outside the documentation paths' do
    write_and_commit('app.rb', "puts 'application change'\n")

    expect(docs_only?).to be(false)
  end

  it 'rejects an empty comparison' do
    expect(docs_only?(@base_revision)).to be(false)
  end

  private

  def docs_only?(head_revision = 'HEAD')
    _output, _error, status = Open3.capture3(
      script,
      @base_revision,
      head_revision,
      chdir: @repository
    )
    status.success?
  end

  def git(*arguments)
    output, error, status = Open3.capture3('git', *arguments, chdir: @repository)
    raise error unless status.success?

    output
  end

  def write_and_commit(path, contents)
    absolute_path = File.join(@repository, path)
    FileUtils.mkdir_p(File.dirname(absolute_path))
    File.write(absolute_path, contents)
    git('add', path)
    git('-c', 'commit.gpgsign=false', 'commit', '--quiet', '-m', "Update #{path}")
  end
end
