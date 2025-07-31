# frozen_string_literal: true

# This class provides a comprehensive wrapper around the Octokit client for GitHub App authentication.
# It handles token generation and refreshing, built-in retry logic, rate limiting, and delegates method calls to the Octokit client.
# Helpful: https://github.com/octokit/handbook?tab=readme-ov-file#github-app-authentication-json-web-token

# Why? In some cases, you may not want to have a static long lived token like a GitHub PAT when authenticating...
# with octokit.rb.
# Most importantly, this class will handle automatic token refreshing, retries, and rate limiting for you out-of-the-box.
# Simply provide the correct environment variables, call `GitHub.new`, and then use the returned object as you would an Octokit client.

# Note: Environment variables have the `GH_` prefix because in GitHub Actions, you cannot use `GITHUB_` for secrets

require "octokit"
require "jwt"
require "redacting_logger"

class GitHub
  TOKEN_EXPIRATION_TIME = 2700 # 45 minutes
  JWT_EXPIRATION_TIME = 600 # 10 minutes

  def initialize(log: nil, app_id: nil, installation_id: nil, app_key: nil, app_algo: nil)
    @log = log || create_default_logger

    # app ids are found on the App's settings page
    @app_id = app_id || fetch_env_var("GH_APP_ID").to_i

    # installation ids look like this:
    # https://github.com/organizations/<org>/settings/installations/<8_digit_id>
    @installation_id = installation_id || fetch_env_var("GH_APP_INSTALLATION_ID").to_i

    # app keys are found on the App's settings page and can be downloaded
    # format: "-----BEGIN...key\n...END-----\n"
    # make sure this key in your env is a single line string with newlines as "\n"
    @app_key = resolve_app_key(app_key)

    @app_algo = app_algo || ENV.fetch("GH_APP_ALGO", "RS256")

    @client = nil
    @token_refresh_time = nil
    @rate_limit_all = nil

    setup_retry_config!
  end

  # A helper method to check the client's current rate limit status before making a request
  # NOTE: This method will sleep for the remaining time until the rate limit resets if the rate limit is hit
  # :param: type [Symbol] the type of rate limit to check (core, search, graphql, etc) - default: :core
  # :return: nil (nothing) - this method will block until the rate limit is reset for the given type
  def wait_for_rate_limit!(type = :core)
    @log.debug("checking rate limit status for type: #{type}")
    # make a request to get the comprehensive rate limit status
    # note: checking the rate limit status does not count against the rate limit in any way
    fetch_rate_limit if @rate_limit_all.nil?

    details = rate_limit_details(type)
    rate_limit = details[:rate_limit]
    resets_at = details[:resets_at]

    @log.debug(
      "rate_limit remaining: #{rate_limit[:remaining]} - " \
      "used: #{rate_limit[:used]} - " \
      "resets_at: #{resets_at} - " \
      "current time: #{Time.now}"
    )

    # exit early if the rate limit is not hit (we have remaining requests)
    unless rate_limit[:remaining].zero?
      update_rate_limit(type)
      return
    end

    # if we make it here, we (probably) have hit the rate limit
    # fetch the rate limit again if we are at zero or if the rate limit reset time is in the past
    fetch_rate_limit if rate_limit[:remaining].zero? || rate_limit[:remaining] < 0 || resets_at < Time.now

    details = rate_limit_details(type)
    rate_limit = details[:rate_limit]
    resets_at = details[:resets_at]

    # exit early if the rate limit is not actually hit (we have remaining requests)
    unless rate_limit[:remaining].zero?
      @log.debug("rate_limit not hit - remaining: #{rate_limit[:remaining]}")
      update_rate_limit(type)
      return
    end

    # calculate the sleep duration - ex: reset time - current time
    sleep_duration = resets_at - Time.now
    @log.debug("sleep_duration: #{sleep_duration}")
    sleep_duration = [sleep_duration, 0].max # ensure sleep duration is not negative
    sleep_duration_and_a_little_more = sleep_duration.ceil + 2 # sleep a little more than the rate limit reset time

    # log the sleep duration and begin the blocking sleep call
    @log.info("github rate_limit hit: sleeping for: #{sleep_duration_and_a_little_more} seconds")
    sleep(sleep_duration_and_a_little_more)

    @log.info("github rate_limit sleep complete - Time.now: #{Time.now}")
  end

  private

  # Creates a default logger if none is provided
  # @return [RedactingLogger] A new logger instance
  def create_default_logger
    RedactingLogger.new($stdout, level: ENV.fetch("GH_APP_LOG_LEVEL", "INFO").upcase)
  end

  # Sets up retry configuration for handling API errors
  # Should the number of retries be reached without success, the last exception will be raised
  def setup_retry_config!
    @retry_sleep = ENV.fetch("GH_APP_SLEEP", 3).to_i
    @retry_tries = ENV.fetch("GH_APP_RETRIES", 10).to_i
    @retry_exponential_backoff = ENV.fetch("GH_APP_EXPONENTIAL_BACKOFF", "false").downcase == "true"
  end

  # Custom retry logic with optional exponential backoff and logging
  # @param retries [Integer] Number of retries to attempt
  # @param sleep_time [Integer] Base sleep time between retries
  # @param block [Proc] The block to execute with retry logic
  # @return [Object] The result of the block execution
  # When exponential backoff is enabled (default is disabled):
  # 1st retry: 3 seconds
  # 2nd retry: 6 seconds
  # 3rd retry: 12 seconds
  # 4th retry: 24 seconds
  # When exponential backoff is disabled:
  # All retries: 3 seconds (fixed rate)
  def retry_request(retries: @retry_tries, sleep_time: @retry_sleep, &block)
    attempt = 0
    begin
      attempt += 1
      yield
    rescue StandardError => e
      if attempt < retries
        if @retry_exponential_backoff
          backoff_time = sleep_time * (2**(attempt - 1)) # Exponential backoff
        else
          backoff_time = sleep_time # Fixed rate
        end
        @log.debug("[retry ##{attempt}] #{e.class}: #{e.message} - sleeping #{backoff_time}s before retry")
        sleep(backoff_time)
        retry
      else
        @log.debug("[retry ##{attempt}] #{e.class}: #{e.message} - max retries exceeded")
        raise e
      end
    end
  end

  def fetch_rate_limit
    @rate_limit_all = retry_request do
      client.get("rate_limit")
    end
  end

  # Update the in-memory "cached" rate limit value for the given rate limit type
  def update_rate_limit(type)
    @rate_limit_all[:resources][type][:remaining] -= 1
  end

  def rate_limit_details(type)
    # fetch the provided rate limit type
    # rate_limit resulting structure: {:limit=>5000, :used=>15, :remaining=>4985, :reset=>1713897293}
    rate_limit = @rate_limit_all[:resources][type]

    # calculate the time the rate limit will reset
    resets_at = Time.at(rate_limit[:reset]).utc

    return {
      rate_limit: rate_limit,
      resets_at: resets_at,
    }
  end

  private

  # Fetches the value of an environment variable and raises an error if it is not set.
  # @param key [String] The name of the environment variable.
  # @return [String] The value of the environment variable.
  def fetch_env_var(key)
    ENV.fetch(key) { raise "environment variable #{key} is not set" }
  end

  # Resolves the app key from various sources
  # @param app_key [String, nil] The app key parameter
  # @return [String] The resolved app key content
  def resolve_app_key(app_key)
    # If app_key is provided as a parameter
    if app_key
      # Check if it's a file path (ends with .pem)
      if app_key.end_with?(".pem")
        unless File.exist?(app_key)
          raise "App key file not found: #{app_key}"
        end

        @log.debug("Loading app key from file: #{app_key}")
        key_content = File.read(app_key)

        if key_content.strip.empty?
          raise "App key file is empty: #{app_key}"
        end

        @log.debug("Successfully loaded app key from file (#{key_content.length} characters)")
        return key_content
      else
        # It's a key string, process escape sequences
        @log.debug("Using provided app key string")
        return normalize_key_string(app_key)
      end
    end

    # Fall back to environment variable
    @log.debug("Loading app key from environment variable")
    env_key = fetch_env_var("GH_APP_KEY")
    normalize_key_string(env_key)
  end

  # Normalizes escape sequences in key strings safely
  # @param key_string [String] The key string to normalize
  # @return [String] The normalized key string
  def normalize_key_string(key_string)
    # Use simple string replacement to avoid ReDoS vulnerability
    # This handles both single \n and multiple consecutive \\n sequences
    key_string.gsub('\\n', "\n")
  end

  # Caches the octokit client if it is not nil and the token has not expired
  # If it is nil or the token has expired, it creates a new client
  # @return [Octokit::Client] The octokit client
  def client
    if @client.nil? || token_expired?
      @client = create_client
    end

    @client
  end

  # A helper method for generating a JWT token for the GitHub App
  # @return [String] The JWT token
  def jwt_token
    private_key = OpenSSL::PKey::RSA.new(@app_key)

    payload = {}.tap do |opts|
      opts[:iat] = Time.now.to_i - 60 # issued at time, 60 seconds in the past to allow for clock drift
      opts[:exp] = opts[:iat] + JWT_EXPIRATION_TIME # JWT expiration time (10 minute maximum)
      opts[:iss] = @app_id # GitHub App ID
    end

    JWT.encode(payload, private_key, @app_algo)
  end

  # Creates a new octokit client and fetches a new installation access token
  # @return [Octokit::Client] The octokit client
  def create_client
    client = ::Octokit::Client.new(bearer_token: jwt_token)
    access_token = client.create_app_installation_access_token(@installation_id)[:token]
    client = ::Octokit::Client.new(access_token:)
    client.auto_paginate = true
    client.per_page = 100
    @token_refresh_time = Time.now
    client
  end

  # GitHub App installation access tokens expire after 1h
  # This method checks if the token has expired and returns true if it has
  # It is very cautious and expires tokens at 45 minutes to account for clock drift
  # @return [Boolean] True if the token has expired, false otherwise
  def token_expired?
    @token_refresh_time.nil? || (Time.now - @token_refresh_time) > TOKEN_EXPIRATION_TIME
  end

  # This method is called when a method is called on the GitHub class that does not exist.
  # It delegates the method call to the Octokit client with built-in retry logic and rate limiting.
  # @param method [Symbol] The name of the method being called.
  # @param args [Array] The arguments passed to the method.
  # @param block [Proc] An optional block passed to the method.
  # @return [Object] The result of the method call on the Octokit client.
  def method_missing(method, *args, **kwargs, &block)
    # Check if retry is explicitly disabled for this call
    disable_retry = kwargs.delete(:disable_retry) || false

    # Determine the rate limit type based on the method name and arguments
    rate_limit_type = case method.to_s
                      when /search_/
                        :search
                      when /graphql/
                        # :nocov:
                        :graphql # I don't actually know of any endpoints that match this method sig yet
                        # :nocov:
                      else
                        # Check if this is a GraphQL call via POST
                        if method.to_s == "post" && args.first&.include?("/graphql")
                          :graphql
                        else
                          :core
                        end
                      end

    # Handle special case for search_issues which can hit secondary rate limits
    if method.to_s == "search_issues"
      request_proc = proc do
        wait_for_rate_limit!(rate_limit_type)
        client.send(method, *args, **kwargs, &block) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
      end

      begin
        if disable_retry
          request_proc.call
        else
          retry_request(&request_proc)
        end
      rescue StandardError => e
        # re-raise the error but if its a secondary rate limit error, just sleep for a minute
        if e.message.include?("exceeded a secondary rate limit")
          @log.warn("GitHub secondary rate limit hit, sleeping for 60 seconds")
          sleep(60)
        end
        raise e
      end
    else
      # For all other methods, use standard retry and rate limiting
      request_proc = proc do
        wait_for_rate_limit!(rate_limit_type)
        client.send(method, *args, **kwargs, &block) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
      end

      if disable_retry
        request_proc.call
      else
        retry_request(&request_proc)
      end
    end
  end

  # This method is called to check if the GitHub class responds to a method.
  # It checks if the Octokit client responds to the method.
  # @param method [Symbol] The name of the method being checked.
  # @param include_private [Boolean] Whether to include private methods in the check.
  # @return [Boolean] True if the Octokit client responds to the method, false otherwise.
  def respond_to_missing?(method, include_private = false)
    client.respond_to?(method, include_private) || super
  end
end
