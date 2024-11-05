# frozen_string_literal: true

require "redacting_logger"

require_relative "version"
require_relative "issue_db/authentication"

class IssueDB
  include Version
  include Authentication

  attr_reader :log
  attr_reader :version

  def initialize(log: nil, octokit_client: nil)
    @log = log || RedactingLogger.new($stdout, level: ENV.fetch("LOG_LEVEL", "INFO").upcase)
    @version = VERSION
    @client = Authentication.login(octokit_client)
  end
end
