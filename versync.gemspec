require_relative "lib/versync/version"

Gem::Specification.new do |spec|
  spec.name = "versync"
  spec.version = Versync::VERSION
  spec.authors = ["Elisson Guímel da Silva"]
  spec.email = ["guigolawliet13@gmail.com"]
  spec.summary = "Keeps documented repository facts (Ruby, Rails, service versions) in sync with reality."
  spec.description = "versync extracts version facts from a Ruby/Rails project's own repository state " \
                      "and generates a canonical VERSIONS.md/versync.json that both humans and AI agents " \
                      "can treat as ground truth."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.homepage = "https://github.com/Guistoff081/versync"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"

  spec.files = Dir["lib/**/*.rb", "exe/*", "LICENSE.txt", "README.md"]
  spec.bindir = "exe"
  spec.executables = ["versync"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "minitest", "~> 5.25"
  spec.add_development_dependency "rake", "~> 13.0"
end
