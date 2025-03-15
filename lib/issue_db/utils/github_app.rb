# frozen_string_literal: true

# This class provides a wrapper around the Octokit client for GitHub App authentication.
# It handles token generation and refreshing, and delegates method calls to the Octokit client.
# Helpful: https://github.com/octokit/handbook?tab=readme-ov-file#github-app-authentication-json-web-token

# Why? In some cases, you may not want to have a static long lived token like a GitHub PAT when authenticating...
# with octokit.rb.
# Most importantly, this class will handle automatic token refreshing for you out-of-the-box. Simply provide the...
# correct environment variables, call `GitHubApp.new`, and then use the returned object as you would an Octokit client.

require "octokit"
require "jwt"

class GitHubApp
  TOKEN_EXPIRATION_TIME = 2700 # 45 minutes
  JWT_EXPIRATION_TIME = 600 # 10 minutes

  def initialize
    # app ids are found on the App's settings page
    @app_id = fetch_env_var("ISSUE_DB_GITHUB_APP_ID").to_i

    # installation ids look like this:
    # https://github.com/organizations/<org>/settings/installations/<8_digit_id>
    @installation_id = fetch_env_var("ISSUE_DB_GITHUB_APP_INSTALLATION_ID").to_i

    # app keys are found on the App's settings page and can be downloaded
    # format: "-----BEGIN...key\n...END-----\n"
    # make sure this key in your env is a single line string with newlines as "\n"
    @app_key = fetch_env_var("ISSUE_DB_GITHUB_APP_KEY").gsub(/\\+n/, "\n")

    @client = nil
    @token_refresh_time = nil
  end

  private

  # Fetches the value of an environment variable and raises an error if it is not set.
  # @param key [String] The name of the environment variable.
  # @return [String] The value of the environment variable.
  def fetch_env_var(key)
    ENV.fetch(key) { raise "environment variable #{key} is not set" }
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

    JWT.encode(payload, private_key, "RS256")
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
  # It delegates the method call to the Octokit client.
  # @param method [Symbol] The name of the method being called.
  # @param args [Array] The arguments passed to the method.
  # @param block [Proc] An optional block passed to the method.
  # @return [Object] The result of the method call on the Octokit client.
  def method_missing(method, *args, &block)
    client.send(method, *args, &block) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
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
