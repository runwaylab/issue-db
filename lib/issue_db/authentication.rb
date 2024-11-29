# frozen_string_literal: true

require "octokit"
require_relative "utils/github_app"

class AuthenticationError < StandardError; end

module Authentication
  def self.login(client = nil)
    # if the client is not nil, use the pre-provided client
    return client unless client.nil?

    # if the client is nil, check for GitHub App env vars first
    # first, check if all three of the following env vars are set and have values
    # ISSUE_DB_GITHUB_APP_ID, ISSUE_DB_GITHUB_APP_INSTALLATION_ID, ISSUE_DB_GITHUB_APP_KEY
    if ENV.fetch("ISSUE_DB_GITHUB_APP_ID", nil) && ENV.fetch("ISSUE_DB_GITHUB_APP_INSTALLATION_ID", nil) && ENV.fetch("ISSUE_DB_GITHUB_APP_KEY", nil)
      return GitHubApp.new
    end

    # if the client is nil and no GitHub App env vars were found, check for the GITHUB_TOKEN
    token = ENV.fetch("GITHUB_TOKEN", nil)
    if token
      octokit = Octokit::Client.new(access_token: token, page_size: 100)
      octokit.auto_paginate = true
      return octokit
    end

    # if we make it here, no valid auth method succeeded
    raise AuthenticationError, "No valid GitHub authentication method was provided"
  end
end
