# frozen_string_literal: true

require_relative "lib/version"

Gem::Specification.new do |spec|
  spec.name          = "issue-db"
  spec.version       = Version::VERSION
  spec.authors       = ["runwaylab", "GrantBirki"]
  spec.license       = "MIT"

  spec.summary       = "A Ruby Gem to use GitHub Issues as a NoSQL JSON document db"
  spec.description   = <<~SPEC_DESC
    A Ruby Gem to use GitHub Issues as a NoSQL JSON document db
  SPEC_DESC

  spec.homepage = "https://github.com/runwaylab/issue-db"
  spec.metadata = {
    "source_code_uri" => "https://github.com/runwaylab/issue-db",
    "documentation_uri" => "https://github.com/runwaylab/issue-db",
    "bug_tracker_uri" => "https://github.com/runwaylab/issue-db/issues"
  }

  spec.add_dependency "redacting-logger", "~> 1.4"
  spec.add_dependency "octokit", ">= 9.2", "< 11.0"
  spec.add_dependency "faraday-retry", "~> 2.2", ">= 2.2.1"
  spec.add_dependency "jwt", ">= 2.9.3", "< 4.0"

  spec.required_ruby_version = Gem::Requirement.new(">= 3.0.0")

  spec.files = %w[LICENSE README.md issue-db.gemspec]
  spec.files += Dir.glob("lib/**/*.rb")
  spec.require_paths = ["lib"]
end
