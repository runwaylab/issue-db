# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/issue_db/utils/github_app"

describe GitHubApp do
  let(:app_id) { "123" }
  let(:installation_id) { "456" }
  let(:app_key) { File.read("spec/fixtures/fake_private_key.pem") }
  let(:jwt_token) { "jwt_token" }
  let(:access_token) { "access_token" }
  let(:client) { instance_double(Octokit::Client) }

  before do
    allow(ENV).to receive(:fetch).with("ISSUE_DB_GITHUB_APP_ID").and_return(app_id)
    allow(ENV).to receive(:fetch).with("ISSUE_DB_GITHUB_APP_INSTALLATION_ID").and_return(installation_id)
    allow(ENV).to receive(:fetch).with("ISSUE_DB_GITHUB_APP_KEY").and_return(app_key)

    allow(client).to receive(:auto_paginate=).with(true).and_return(true)
    allow(client).to receive(:per_page=).with(100).and_return(100)
  end

  describe "#initialize" do
    it "initializes with environment variables" do
      github_app = GitHubApp.new
      expect(github_app.instance_variable_get(:@app_id)).to eq(app_id.to_i)
      expect(github_app.instance_variable_get(:@installation_id)).to eq(installation_id.to_i)
      expect(github_app.instance_variable_get(:@app_key)).to eq(app_key.gsub(/\\+n/, "\n"))
    end
  end

  describe "#client" do
    let(:github_app) { GitHubApp.new }

    before do
      allow(github_app).to receive(:jwt_token).and_return(jwt_token)
      allow(client).to receive(:create_app_installation_access_token).with(installation_id.to_i).and_return(token: access_token)
      allow(Octokit::Client).to receive(:new).with(bearer_token: jwt_token).and_return(client)
      allow(Octokit::Client).to receive(:new).with(access_token: access_token).and_return(client)
    end

    context "when client is nil" do
      it "creates a new client" do
        expect(github_app.send(:client)).to eq(client)
      end
    end

    context "when token is expired" do
      it "creates a new client" do
        github_app.instance_variable_set(:@token_refresh_time, Time.now - GitHubApp::TOKEN_EXPIRATION_TIME - 1)
        expect(github_app.send(:client)).to eq(client)
      end
    end

    context "when token is not expired" do
      it "returns the cached client" do
        github_app.instance_variable_set(:@client, client)
        github_app.instance_variable_set(:@token_refresh_time, Time.now)
        expect(github_app.send(:client)).to eq(client)
      end
    end
  end

  describe "#jwt_token" do
    it "generates a JWT token" do
      github_app = GitHubApp.new
      private_key = OpenSSL::PKey::RSA.new(app_key.gsub(/\\+n/, "\n"))
      payload = {
        iat: Time.now.to_i - 60,
        exp: Time.now.to_i - 60 + GitHubApp::JWT_EXPIRATION_TIME,
        iss: app_id.to_i
      }
      token = JWT.encode(payload, private_key, "RS256")
      expect(github_app.send(:jwt_token)).to eq(token)
    end
  end

  describe "#method_missing" do
    it "delegates method calls to the Octokit client" do
      github_app = GitHubApp.new
      allow(github_app).to receive(:client).and_return(client)
      expect(client).to receive(:rate_limit)
      github_app.rate_limit
    end
  end

  describe "#respond_to_missing?" do
    it "checks if the Octokit client responds to a method" do
      github_app = GitHubApp.new
      allow(github_app).to receive(:client).and_return(client)
      allow(client).to receive(:respond_to?).with(:rate_limit, false).and_return(true)
      expect(github_app.respond_to?(:rate_limit)).to be true
    end
  end
end
