# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/issue_db/authentication"

describe Authentication do
  let(:client) { instance_double(Octokit::Client).as_null_object }
  let(:token) { "fake_token" }

  before(:each) do
    allow(Octokit::Client).to receive(:new).and_return(client)
  end

  it "returns the pre-provided client" do
    expect(Authentication::login(client)).to eq(client)
  end

  it "returns a hydrated octokit client from a GitHub PAT" do
    expect(Octokit::Client).to receive(:new)
      .with(access_token: token, page_size: 100)
      .and_return(client)
    expect(ENV).to receive(:fetch).with("ISSUE_DB_GITHUB_APP_ID", nil).and_return(nil)
    expect(ENV).to receive(:fetch).with("GITHUB_TOKEN", nil).and_return(token)
    expect(Authentication.login).to eq(client)
  end

  it "returns a hydrated octokit client from a GitHub App" do
    expect(ENV).to receive(:fetch).with("ISSUE_DB_GITHUB_APP_ID", nil).and_return("123")
    expect(ENV).to receive(:fetch).with("ISSUE_DB_GITHUB_APP_INSTALLATION_ID", nil).and_return("456")
    expect(ENV).to receive(:fetch).with("ISSUE_DB_GITHUB_APP_KEY", nil).and_return("-----KEY-----")

    expect(GitHubApp).to receive(:new).and_return(client)
    expect(Authentication.login).to eq(client)
  end

  it "raises an authentication error when no auth methods pass for octokit" do
    expect(ENV).to receive(:fetch).with("ISSUE_DB_GITHUB_APP_ID", nil).and_return(nil)
    expect(ENV).to receive(:fetch).with("GITHUB_TOKEN", nil).and_return(nil)
    expect do
      Authentication.login
    end.to raise_error(
      AuthenticationError,
      "No valid GitHub authentication method was provided"
    )
  end
end
