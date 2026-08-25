require "test_helper"

class GitInfoTest < Minitest::Test
  def test_returns_head_sha_for_a_git_repository
    with_temp_project do |dir|
      system("git", "-C", dir, "init", "-q")
      system("git", "-C", dir, "config", "user.email", "test@example.com")
      system("git", "-C", dir, "config", "user.name", "Test")
      File.write(File.join(dir, "file.txt"), "content")
      system("git", "-C", dir, "add", "file.txt")
      system("git", "-C", dir, "commit", "-q", "-m", "initial")

      sha = Versync::GitInfo.current_sha(dir)

      assert_match(/\A[0-9a-f]{40}\z/, sha)
    end
  end

  def test_returns_nil_when_not_a_git_repository
    with_temp_project { |dir| assert_nil Versync::GitInfo.current_sha(dir) }
  end
end
