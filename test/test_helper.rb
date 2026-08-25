require "versync"
require "minitest/autorun"
require "tmpdir"
require "fileutils"

module VersyncTestHelpers
  def with_temp_project
    Dir.mktmpdir do |dir|
      yield dir
    end
  end

  # Dir.glob("#{path}/*") does NOT match dotfiles (e.g. .ruby-version,
  # .versync.yml) — most fixtures need exactly those files, so this
  # passes FNM_DOTMATCH and filters out "." and "..".
  def copy_fixture(fixture_name, project_root)
    fixture_path = File.join(__dir__, "fixtures", fixture_name)
    entries = Dir.glob("#{fixture_path}/*", File::FNM_DOTMATCH)
                 .reject { |entry| %w[. ..].include?(File.basename(entry)) }
    FileUtils.cp_r(entries, project_root)
  end
end

Minitest::Test.include(VersyncTestHelpers)
