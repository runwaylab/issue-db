# frozen_string_literal: true

require_relative "cache"
require_relative "models/record"
require_relative "utils/generate"

class RecordNotFound < StandardError; end

class Database
  include Cache
  include Generate

  # :param: log [Logger] a logger object to use for logging
  # :param: client [Octokit::Client] an Octokit::Client object to use for interacting with the GitHub API
  # :param: repo [Repository] a Repository object that represents the GitHub repository to use as the datastore
  # :param: label [String] the label to use for issues managed in the datastore by this library
  # :param: cache_expiry [Integer] the number of seconds to cache issues in memory (default: 60)
  # :return: A new Database object
  def initialize(log, client, repo, label, cache_expiry)
    @log = log
    @client = client
    @repo = repo
    @label = label
    @cache_expiry = cache_expiry
    @issues = nil
    @issues_last_updated = nil
  end

  # Create a new issue/record in the database
  # This will return the newly created issue as a Record object (parsed)
  # :param: key [String] the key (issue title) to create
  # :param: data [Hash] the data to use for the issue body
  # :param: options [Hash] a hash of options containing extra data such as body_before and body_after
  # :return: The newly created issue as a Record object
  # usage example:
  # data = { color: "blue", cool: true, popularity: 100, tags: ["tag1", "tag2"] }
  # options = { body_before: "some text before the data", body_after: "some text after the data", include_closed: true }
  # db.create("event123", {cool: true, data: "here"}, options)
  def create(key, data, options = {})
    @log.debug("attempting to create: #{key}")
    issue = find_issue_by_key(key, options, create_mode: true)
    if issue
      @log.warn("skipping issue creation and returning existing issue - an issue already exists with the key: #{key}")
      return Record.new(issue)
    end

    # if we make it here, no existing issues were found so we can safely create one

    body = generate(data, body_before: options[:body_before], body_after: options[:body_after])

    # if we make it here, no existing issues were found so we can safely create one
    issue = @client.create_issue(@repo.full_name, key, body, { labels: @label })

    # ensure the cache is initialized before appending
    issues if @issues.nil?
    @issues << issue

    @log.debug("issue created: #{key}")
    return Record.new(issue)
  end

  # Read an issue/record from the database
  # This will return the issue as a Record object (parsed)
  # :param: key [String] the key (issue title) to read
  # :param: options [Hash] a hash of options to pass through to the search method
  # :return: The issue as a Record object
  def read(key, options = {})
    @log.debug("attempting to read: #{key}")
    issue = find_issue_by_key(key, options)
    @log.debug("issue found: #{key}")
    return Record.new(issue)
  end

  # Update an issue/record in the database
  # This will return the updated issue as a Record object (parsed)
  # :param: key [String] the key (issue title) to update
  # :param: data [Hash] the data to use for the issue body
  # :param: options [Hash] a hash of options containing extra data such as body_before and body_after
  # :return: The updated issue as a Record object
  # usage example:
  # data = { color: "blue", cool: true, popularity: 100, tags: ["tag1", "tag2"] }
  # options = { body_before: "some text before the data", body_after: "some text after the data", include_closed: true }
  # db.update("event123", {cool: true, data: "here"}, options)
  def update(key, data, options = {})
    @log.debug("attempting to update: #{key}")
    issue = find_issue_by_key(key, options)

    body = generate(data, body_before: options[:body_before], body_after: options[:body_after])

    updated_issue = @client.update_issue(@repo.full_name, issue.number, key, body)

    # update the issue in the cache using the reference we have
    index = @issues.index(issue)
    if index
      @issues[index] = updated_issue
    else
      @log.warn("issue not found in cache during update: #{key}")
      # Force a cache refresh to ensure consistency
      update_issue_cache!
    end

    @log.debug("issue updated: #{key}")
    return Record.new(updated_issue)
  end

  # Delete an issue/record from the database - in this context, "delete" means to close the issue as "completed"
  # :param: key [String] the key (issue title) to delete
  # :param: options [Hash] a hash of options to pass through to the search method
  # :return: The deleted issue as a Record object (parsed) - it may contain useful data
  def delete(key, options = {})
    @log.debug("attempting to delete: #{key}")
    issue = find_issue_by_key(key, options)

    deleted_issue = @client.close_issue(@repo.full_name, issue.number)

    # update the issue in the cache using the reference we have
    index = @issues.index(issue)
    if index
      @issues[index] = deleted_issue
    else
      @log.warn("issue not found in cache during delete: #{key}")
      # Force a cache refresh to ensure consistency
      update_issue_cache!
    end

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
  # :param: create_mode [Boolean] a flag to indicate whether or not we are in create mode
  # :return: A direct reference to the issue as a Hash object if found, otherwise throws a RecordNotFound error
  # ... unless create_mode is true, in which case it returns nil as a signal to proceed with creating the issue
  def find_issue_by_key(key, options = {}, create_mode: false)
    issue = issues.find do |issue|
      issue[:title] == key && (options[:include_closed] || issue[:state] == "open")
    end

    if issue.nil?
      @log.debug("no issue found in cache for: #{key}")
      return nil if create_mode

      not_found!(key)
    end

    @log.debug("issue found in cache for: #{key}")
    return issue
  end

  # A helper method to fetch all issues from the repo and update the issues cache
  # It is cache aware
  def issues
    # update the issues cache if it is nil
    update_issue_cache! if @issues.nil?

    # update the cache if it has expired
    if @issues_last_updated && (Time.now - @issues_last_updated) > @cache_expiry
      @log.debug("issue cache expired - last updated: #{@issues_last_updated} - refreshing now")
      update_issue_cache!
    end

    return @issues
  end
end
