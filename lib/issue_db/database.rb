# frozen_string_literal: true

require_relative "cache"
require_relative "utils/throttle"
require_relative "models/record"
require_relative "utils/generate"

# class DatabaseError < StandardError; end

class Database
  include Cache
  include Throttle
  include Generate

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

  def create(key, data, options = {})
    @log.debug("attempting to create: #{key}")

    issue = find_issue_by_key(key, options)
    if issue
      @log.warn("skipping issue creation and returning existing issue - an issue already exists with the key: #{key}")
      return issue
    end

    body = generate(data, body_before: options[:body_before], body_after: options[:body_after])

    # if we make it here, no existing issues were found so we can safely create one
    issue = Retryable.with_context(:default) do
      wait_for_rate_limit!
      @client.create_issue(@repo.full_name, key, body, { labels: @label })
    end

    # append the newly created issue to the issues cache
    @issues << issue

    return Record.new(issue)
  end

  def read(key, options = {})
    @log.debug("attempting to read: #{key}")
    return find_issue_by_key(key, options)
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

  # A helper method to search through the issues cache and return the first issue that matches the given key
  # :param: key [String] the key (issue title) to search for
  # :param: options [Hash] a hash of options to pass through to the search method
  # :return: The issue as a Record object if found, otherwise nil
  def find_issue_by_key(key, options = {})
    issues.each do |issue|
      # if there is an exact match and the issue is open, we found a match
      # if include_closed is true, we will include closed issues (all types) in the search
      next unless issue[:title] == key && ((options[:include_closed]) || issue[:state] == "open")

      return Record.new(issue)
    end

    # if we make it here, no issue was found in the cache for the given key (title)
    @log.debug("no issue found in cache for: #{key}")
    return nil
  end

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
