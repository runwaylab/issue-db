# frozen_string_literal: true

require "octokit"
require_relative "utils/github_app"

class AuthenticationError < StandardError; end

module Authentication
  def self.login(client = nil, log = nil)
    # if the client is not nil, use the pre-provided client
    unless client.nil?
      log.debug("using pre-provided client") if log
      return client
    end

    # if the client is nil, check for GitHub App env vars first
    # first, check if all three of the following env vars are set and have values
    # ISSUE_DB_GITHUB_APP_ID, ISSUE_DB_GITHUB_APP_INSTALLATION_ID, ISSUE_DB_GITHUB_APP_KEY
    if ENV.fetch("ISSUE_DB_GITHUB_APP_ID", nil) && ENV.fetch("ISSUE_DB_GITHUB_APP_INSTALLATION_ID", nil) && ENV.fetch("ISSUE_DB_GITHUB_APP_KEY", nil)
      log.debug("using github app authentication") if log
      return GitHubApp.new
    end

    # if the client is nil and no GitHub App env vars were found, check for the ISSUE_DB_GITHUB_TOKEN
    token = ENV.fetch("ISSUE_DB_GITHUB_TOKEN", nil)
    if token
      log.debug("using github token authentication") if log
      octokit = Octokit::Client.new(access_token: token, page_size: 100)
      octokit.auto_paginate = true
      return octokit
    end

    # if we make it here, no valid auth method succeeded
    raise AuthenticationError, "No valid GitHub authentication method was provided"
  end
end
