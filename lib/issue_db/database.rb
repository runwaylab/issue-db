# frozen_string_literal: true

require_relative "cache"
require_relative "utils/throttle"
require_relative "models/record"
require_relative "utils/generate"

class RecordNotFound < StandardError; end

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
      return Record.new(issue)
    end

    body = generate(data, body_before: options[:body_before], body_after: options[:body_after])

    # if we make it here, no existing issues were found so we can safely create one
    issue = Retryable.with_context(:default) do
      wait_for_rate_limit!
      @client.create_issue(@repo.full_name, key, body, { labels: @label })
    end

    # append the newly created issue to the issues cache
    @issues << issue

    @log.debug("issue created: #{key}")
    return Record.new(issue)
  end

  def read(key, options = {})
    @log.debug("attempting to read: #{key}")
    issue = find_issue_by_key(key, options)
    @log.debug("issue found: #{key}")
    return Record.new(issue)
  end

  def update(key, data, options = {})
    @log.debug("attempting to update: #{key}")
    issue = find_issue_by_key(key, options)

    body = generate(data, body_before: options[:body_before], body_after: options[:body_after])

    updated_issue = Retryable.with_context(:default) do
      wait_for_rate_limit!
      @client.update_issue(@repo.full_name, issue.number, key, body)
    end

    # update the issue in the cache using the reference we have
    @issues[@issues.index(issue)] = updated_issue

    @log.debug("issue updated: #{key}")
    return Record.new(updated_issue)
  end

  def delete(key, options = {})
    @log.debug("attempting to delete: #{key}")
    issue = find_issue_by_key(key, options)

    deleted_issue = Retryable.with_context(:default) do
      wait_for_rate_limit!
      @client.close_issue(@repo.full_name, issue.number)
    end

    # remove the issue from the cache
    @issues.delete(issue)

    # return the deleted issue as a Record object as it may contain useful data
    return Record.new(deleted_issue)
  end

  # List all keys in the database
  # This will return an array of strings that represent the issue titles that are "keys" in the database
  # :param: options [Hash] a hash of options to pass through to the search method
  # :return: An array of strings that represent the issue titles that are "keys" in the database
  # usage example:
  # options = {include_closed: true}
  # keys = db.list_keys(options)
  def list_keys(options = {})
    keys = issues.select do |issue|
      options[:include_closed] || issue[:state] == "open"
    end.map do |issue|
      issue[:title]
    end

    return keys
  end

  # List all issues/record in the database as Record objects (parsed)
  # This will return an array of Record objects that represent the issues in the database
  # :param: options [Hash] a hash of options to pass through to the search method
  # :return: An array of Record objects that represent the issues in the database
  # usage example:
  # options = {include_closed: true}
  # records = db.list(options)
  def list(options = {})
    records = issues.select do |issue|
      options[:include_closed] || issue[:state] == "open"
    end.map do |issue|
      Record.new(issue)
    end

    return records
  end

  # Force a refresh of the issues cache
  # This will update the issues cache with the latest issues from the repo
  # :return: The updated issue cache as a list of issues (Hash objects not parsed)
  def refresh!
    update_issue_cache!
  end

  protected

  def not_found!(key)
    raise RecordNotFound, "no record found for key: #{key}"
  end

  # A helper method to search through the issues cache and return the first issue that matches the given key
  # :param: key [String] the key (issue title) to search for
  # :param: options [Hash] a hash of options to pass through to the search method
  # :return: A direct reference to the issue as a Hash object if found, otherwise throws a RecordNotFound error
  def find_issue_by_key(key, options = {})
    issue = issues.find do |issue|
      issue[:title] == key && (options[:include_closed] || issue[:state] == "open")
    end

    if issue.nil?
      @log.debug("no issue found in cache for: #{key}")
      not_found!(key)
    end

    @log.debug("issue found in cache for: #{key}")
    return issue
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
