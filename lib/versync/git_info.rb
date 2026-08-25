require "shellwords"

module Versync
  module GitInfo
    def self.current_sha(project_root)
      sha = `git -C #{project_root.shellescape} rev-parse HEAD 2>/dev/null`.strip
      sha.empty? ? nil : sha
    rescue Errno::ENOENT
      nil
    end
  end
end
