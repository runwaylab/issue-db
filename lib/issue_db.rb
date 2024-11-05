# frozen_string_literal: true

require "redacting_logger"

require_relative "version"
require_relative "issue_db/utils/retry"
require_relative "issue_db/authentication"
require_relative "issue_db/models/repository"

class IssueDB
  include Version
  include Authentication

  attr_reader :log
  attr_reader :version

  # Create a new IssueDB object
  # :param repo: The GitHub repository to use as the datastore (org/repo format) [required]
  # :param log: An optional logger - created for you by default
  # :param octokit_client: An optional pre-hydrated Octokit::Client object
  def initialize(repo, log: nil, octokit_client: nil)
    @log = log || RedactingLogger.new($stdout, level: ENV.fetch("LOG_LEVEL", "INFO").upcase)
    Retry.setup!(log: @log)
    @version = VERSION
    @client = Authentication.login(octokit_client)
    @repo = Repository.new(repo)
  end
end
