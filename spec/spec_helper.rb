# frozen_string_literal: true

# ENV["APP_ENV"] = "test"

require "simplecov"
require "rspec"
require "simplecov-erb"

REPO = "runwaylab/issue-db"
FAKE_TOKEN = "fake_token"

COV_DIR = File.expand_path("../coverage", File.dirname(__FILE__))

SimpleCov.root File.expand_path("..", File.dirname(__FILE__))
SimpleCov.coverage_dir COV_DIR

SimpleCov.formatters = [
  SimpleCov::Formatter::HTMLFormatter,
  SimpleCov::Formatter::ERBFormatter
]

SimpleCov.minimum_coverage 100

SimpleCov.at_exit do
  File.write("#{COV_DIR}/total-coverage.txt", SimpleCov.result.covered_percent)
  SimpleCov.result.format!
end

SimpleCov.start do
  add_filter "spec/"
  add_filter "vendor/gems/"
end

# Globally capture all sleep calls
RSpec.configure do |config|
  config.before(:each) do
    allow(Kernel).to receive(:sleep)
    allow_any_instance_of(Kernel).to receive(:sleep)
    allow_any_instance_of(Object).to receive(:sleep)
  end
end

require "vcr"
require "webmock/rspec"

VCR.configure do |config|
  config.cassette_library_dir = "spec/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.filter_sensitive_data("<GITHUB_TOKEN>") { ENV["ISSUE_DB_GITHUB_TOKEN"] }
  config.filter_sensitive_data("<GITHUB_TOKEN>") { ENV["GITHUB_TOKEN"] }
  config.filter_sensitive_data("<JWT_TOKEN>") do |interaction|
    if interaction.request.headers["Authorization"]
      interaction.request.headers["Authorization"].first
    end
  end
  # config.default_cassette_options = { record: :new_episodes }
end
