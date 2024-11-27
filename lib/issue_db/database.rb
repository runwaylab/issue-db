# frozen_string_literal: true

require_relative "cache"
require_relative "utils/throttle"

# class DatabaseError < StandardError; end

class Database
  include Cache
  include Throttle

  def initialize(log, client, repo, label, cache_expiry)
    @log = log
    @client = client
    @repo = repo
    @label = label
    @cache_expiry = cache_expiry
    @rate_limit_all = nil
    @issues = nil
    @issues_last_updated = nil
  end

  def create
    "TODO"
  end

  def read(key, include_closed: false)
    @log.debug("attempting to read: #{key}")

    @issues.each do |issue|
      # if there is an exact match and the issue is open, we found a match
      # if include_closed is true, we will include closed issues (all types) in the search
      next unless issue[:title] == key && ((include_closed) || issue[:state] == "open")

      return issue
    end

    # if we make it here, no issue was found in the cache for the given key (title)
    @log.debug("no issue found in cache for: #{key}")
    return nil
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

  def refresh!
    update_issue_cache!
  end

  protected

  def issues
    # update the issues cache if it is nil
    update_issue_cache! if @issues.nil?

    # update the cache if it has expired
    issues_cache_expired = (Time.now - @issues_last_updated) > @cache_expiry
    if issues_cache_expired
      @log.debug("issue cache expired - last updated: #{@issues_last_updated} - refreshing now")
      update_issue_cache!
    end

    return @issues
  end
end
