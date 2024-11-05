# frozen_string_literal: true

require_relative "utils/throttle"

# class DatabaseError < StandardError; end

class Database
  include Throttle

  def initialize(log, client, repo)
    @log = log
    @client = client
    @repo = repo
  end

  def create
    "TODO"
  end

  def read(issue_number)
    @log.debug("reading issue: #{issue_number}")
    issue = Retryable.with_context(:default) do
      wait_for_rate_limit!
      @client.issue(@repo.full_name, issue_number)
    end
    return issue
  end

  def update
    "TODO"
  end

  def delete
    "TODO"
  end

  def list
    "TODO"
  end
end
