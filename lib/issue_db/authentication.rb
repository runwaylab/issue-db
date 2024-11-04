# frozen_string_literal: true

require "octokit"

module Authentication
  def login(client = nil)
    # if the client is not nil, use the pre-provided client
    return client unless client.nil?

    # if the client is nil, check for GitHub App env vars
    # TODO

    # if the client is nil and no GitHub App env vars were found, check for the GITHUB_TOKEN
    token = ENV.fetch("GITHUB_TOKEN", nil)
    octokit = Octokit::Client.new(access_token: token, page_size: 100)
    octokit.auto_paginate = true

    return octokit
  end
end
