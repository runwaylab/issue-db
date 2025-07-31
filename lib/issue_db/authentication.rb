# frozen_string_literal: true

require "octokit"
require_relative "utils/github"

module IssueDB
  class AuthenticationError < StandardError; end

  module Authentication
    def self.login(client = nil, log = nil, app_id: nil, installation_id: nil, app_key: nil, app_algo: nil)
      # if the client is not nil, use the pre-provided client
      unless client.nil?
        log.debug("using pre-provided client") if log
        return client
      end

      # if GitHub App parameters are provided, use them first
      if app_id && installation_id && app_key
        log.debug("using provided github app authentication parameters") if log
        return IssueDB::Utils::GitHub.new(log:, app_id:, installation_id:, app_key:, app_algo:)
      end

      # if the client is nil, check for GitHub App env vars
      # first, check if all three of the following env vars are set and have values
      # ISSUE_DB_GITHUB_APP_ID, ISSUE_DB_GITHUB_APP_INSTALLATION_ID, ISSUE_DB_GITHUB_APP_KEY
      env_app_id = ENV.fetch("ISSUE_DB_GITHUB_APP_ID", nil)
      env_installation_id = ENV.fetch("ISSUE_DB_GITHUB_APP_INSTALLATION_ID", nil)
      env_app_key = ENV.fetch("ISSUE_DB_GITHUB_APP_KEY", nil)
      if env_app_id && env_installation_id && env_app_key
        log.debug("using github app authentication from environment variables") if log
        return IssueDB::Utils::GitHub.new(log:, app_id: env_app_id, installation_id: env_installation_id, app_key: env_app_key)
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
end
