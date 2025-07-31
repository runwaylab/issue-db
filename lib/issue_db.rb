# frozen_string_literal: true

require "redacting_logger"

require_relative "version"
require_relative "issue_db/utils/init"
require_relative "issue_db/authentication"
require_relative "issue_db/models/repository"
require_relative "issue_db/database"

module IssueDB
  class Client
    include Version
    include Authentication
    include Init

    attr_reader :log
    attr_reader :version

    # Create a new IssueDB::Client object
    # :param repo: The GitHub repository to use as the datastore (org/repo format) [required]
    # :param log: An optional logger - created for you by default
    # :param octokit_client: An optional pre-hydrated Octokit::Client object
    # :param label: The label to use for issues managed in the datastore by this library
    # :param cache_expiry: The number of seconds to cache issues in memory (default: 60)
    # :param init: Whether or not to initialize the database on object creation (default: true) - idempotent
    # :return: A new IssueDB::Client object
    def initialize(repo, log: nil, octokit_client: nil, label: nil, cache_expiry: nil, init: true)
      @log = log || RedactingLogger.new($stdout, level: ENV.fetch("LOG_LEVEL", "INFO").upcase)
      @version = VERSION
      @client = Authentication.login(octokit_client, @log)
      @repo = Repository.new(repo)
      @label = label || ENV.fetch("ISSUE_DB_LABEL", "issue-db")
      @cache_expiry = cache_expiry || ENV.fetch("ISSUE_DB_CACHE_EXPIRY", 60).to_i
      init! if init
    end

    def create(key, data, options = {})
      db.create(key, data, options)
    end

    def read(key, options = {})
      db.read(key, options)
    end

    def update(key, data, options = {})
      db.update(key, data, options)
    end

    def delete(key, options = {})
      db.delete(key, options)
    end

    def list(options = {})
      db.list(options)
    end

    def list_keys(options = {})
      db.list_keys(options)
    end

    def refresh!
      db.refresh!
    end

    protected

    def db
      @db ||= Database.new(@log, @client, @repo, @label, @cache_expiry)
    end
  end
end
