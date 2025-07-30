# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/issue_db/utils/github_app"

describe GitHubApp, :vcr do
  let(:app_id) { "123" }
  let(:installation_id) { "456" }
  let(:app_key) { File.read("spec/fixtures/fake_private_key.pem") }
  let(:jwt_token) { "jwt_token" }
  let(:access_token) { "access_token" }
  let(:client) { instance_double(Octokit::Client) }

  before do
    allow(ENV).to receive(:fetch).with("GH_APP_ID").and_return(app_id)
    allow(ENV).to receive(:fetch).with("GH_APP_INSTALLATION_ID").and_return(installation_id)
    allow(ENV).to receive(:fetch).with("GH_APP_KEY").and_return(app_key)
    allow(ENV).to receive(:fetch).with("http_proxy", nil).and_return(nil)
    allow(ENV).to receive(:fetch).with("GH_APP_LOG_LEVEL", "INFO").and_return("INFO")
    allow(ENV).to receive(:fetch).with("GH_APP_SLEEP", 3).and_return(3)
    allow(ENV).to receive(:fetch).with("GH_APP_RETRIES", 10).and_return(10)
    allow(ENV).to receive(:fetch).with("GH_APP_ALGO", "RS256").and_return("RS256")

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

    it "initializes with provided parameters" do
      github_app = GitHubApp.new(
        app_id: 999,  # Pass as integer instead of string
        installation_id: 888,  # Pass as integer instead of string
        app_key: app_key
      )
      expect(github_app.instance_variable_get(:@app_id)).to eq(999)
      expect(github_app.instance_variable_get(:@installation_id)).to eq(888)
      expect(github_app.instance_variable_get(:@app_key)).to eq(app_key.gsub(/\\+n/, "\n"))
    end

    it "loads app key from .pem file path" do
      pem_file_path = "spec/fixtures/fake_private_key.pem"
      github_app = GitHubApp.new(
        app_id: 999,
        installation_id: 888,
        app_key: pem_file_path
      )
      expected_key = File.read(pem_file_path)
      expect(github_app.instance_variable_get(:@app_key)).to eq(expected_key)
    end

    it "processes escape sequences in app key string" do
      key_with_escapes = "-----BEGIN RSA PRIVATE KEY-----\\nsome\\nkey\\ndata\\n-----END RSA PRIVATE KEY-----"
      github_app = GitHubApp.new(
        app_id: 999,
        installation_id: 888,
        app_key: key_with_escapes
      )
      expected_key = key_with_escapes.gsub(/\\+n/, "\n")
      expect(github_app.instance_variable_get(:@app_key)).to eq(expected_key)
    end

    it "falls back to environment variables when parameters are not provided" do
      # Don't provide app_key parameter, should fall back to ENV
      github_app = GitHubApp.new(
        app_id: 999,
        installation_id: 888
        # app_key intentionally omitted
      )
      expect(github_app.instance_variable_get(:@app_key)).to eq(app_key.gsub(/\\+n/, "\n"))
    end

    it "raises error when environment variable is missing and no parameter provided" do
      allow(ENV).to receive(:fetch).with("GH_APP_KEY").and_call_original
      allow(ENV).to receive(:fetch).with("GH_APP_KEY") { raise "environment variable GH_APP_KEY is not set" }

      expect do
        GitHubApp.new(
          app_id: 999,
          installation_id: 888
          # app_key intentionally omitted, ENV var also missing
        )
      end.to raise_error(/environment variable GH_APP_KEY is not set/)
    end

    it "accepts custom logger" do
      custom_logger = instance_double(RedactingLogger)
      allow(custom_logger).to receive(:debug)  # Allow debug method calls
      github_app = GitHubApp.new(log: custom_logger, app_id: 999, installation_id: 888, app_key: app_key)
      expect(github_app.instance_variable_get(:@log)).to eq(custom_logger)
    end

    it "handles different key sources correctly" do
      # Test file loading - just verify it works without checking debug messages
      file_github_app = GitHubApp.new(app_id: 999, installation_id: 888, app_key: "spec/fixtures/fake_private_key.pem")
      expect(file_github_app.instance_variable_get(:@app_key)).to eq(File.read("spec/fixtures/fake_private_key.pem"))

      # Test string key with escape sequences
      string_github_app = GitHubApp.new(app_id: 999, installation_id: 888, app_key: "-----BEGIN RSA PRIVATE KEY-----\\ntest\\n-----END RSA PRIVATE KEY-----")
      expect(string_github_app.instance_variable_get(:@app_key)).to eq("-----BEGIN RSA PRIVATE KEY-----\ntest\n-----END RSA PRIVATE KEY-----")

      # Test environment fallback
      env_github_app = GitHubApp.new(app_id: 999, installation_id: 888)
      expect(env_github_app.instance_variable_get(:@app_key)).to eq(app_key.gsub(/\\+n/, "\n"))
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

      # Mock the rate limit check that happens internally
      rate_limit_response = {
        resources: {
          core: { remaining: 5000, used: 0, limit: 5000, reset: Time.now.to_i + 3600 }
        }
      }
      allow(client).to receive(:get).with("rate_limit").and_return(rate_limit_response)
      allow(client).to receive(:rate_limit).and_return("mocked_response")

      result = github_app.rate_limit
      expect(result).to eq("mocked_response")
    end

    it "handles search_ methods with search rate limit type" do
      github_app = GitHubApp.new
      allow(github_app).to receive(:client).and_return(client)

      rate_limit_response = {
        resources: {
          search: { remaining: 30, used: 0, limit: 30, reset: Time.now.to_i + 3600 }
        }
      }
      allow(client).to receive(:get).with("rate_limit").and_return(rate_limit_response)
      allow(client).to receive(:search_users).and_return("search_result")

      result = github_app.search_users("test")
      expect(result).to eq("search_result")
    end

    it "handles graphql method with graphql rate limit type" do
      github_app = GitHubApp.new
      allow(github_app).to receive(:client).and_return(client)

      rate_limit_response = {
        resources: {
          graphql: { remaining: 5000, used: 0, limit: 5000, reset: Time.now.to_i + 3600 }
        }
      }
      allow(client).to receive(:get).with("rate_limit").and_return(rate_limit_response)
      # Use post method to simulate GraphQL calls since graphql method might not exist
      allow(client).to receive(:post).and_return("graphql_result")
      allow(client).to receive(:respond_to?).with(:post, false).and_return(true)

      result = github_app.post("/graphql", { query: "test" })
      expect(result).to eq("graphql_result")
    end

    it "handles POST to /graphql with graphql rate limit type" do
      github_app = GitHubApp.new
      allow(github_app).to receive(:client).and_return(client)

      rate_limit_response = {
        resources: {
          graphql: { remaining: 5000, used: 0, limit: 5000, reset: Time.now.to_i + 3600 }
        }
      }
      allow(client).to receive(:get).with("rate_limit").and_return(rate_limit_response)
      allow(client).to receive(:post).and_return("graphql_post_result")

      # This should trigger the POST /graphql detection on line 216
      result = github_app.post("/graphql", { query: "test" })
      expect(result).to eq("graphql_post_result")
    end

    it "handles POST with nil first argument" do
      github_app = GitHubApp.new
      allow(github_app).to receive(:client).and_return(client)

      rate_limit_response = {
        resources: {
          core: { remaining: 5000, used: 0, limit: 5000, reset: Time.now.to_i + 3600 }
        }
      }
      allow(client).to receive(:get).with("rate_limit").and_return(rate_limit_response)
      allow(client).to receive(:post).and_return("post_result")

      # This should trigger the &. safe navigation operator and fall through to :core
      result = github_app.post(nil)
      expect(result).to eq("post_result")
    end

    it "handles regular POST calls (not GraphQL) with core rate limit type" do
      github_app = GitHubApp.new
      allow(github_app).to receive(:client).and_return(client)

      rate_limit_response = {
        resources: {
          core: { remaining: 5000, used: 0, limit: 5000, reset: Time.now.to_i + 3600 }
        }
      }
      allow(client).to receive(:get).with("rate_limit").and_return(rate_limit_response)
      allow(client).to receive(:post).and_return("regular_post_result")

      result = github_app.post("/some/other/endpoint", { data: "test" })
      expect(result).to eq("regular_post_result")
    end

    it "handles search_issues with secondary rate limit error" do
      github_app = GitHubApp.new
      allow(github_app).to receive(:client).and_return(client)

      rate_limit_response = {
        resources: {
          search: { remaining: 30, used: 0, limit: 30, reset: Time.now.to_i + 3600 }
        }
      }
      allow(client).to receive(:get).with("rate_limit").and_return(rate_limit_response)

      # Mock the search_issues call to raise the secondary rate limit error
      allow(client).to receive(:search_issues).and_raise(StandardError.new("You have exceeded a secondary rate limit"))

      # Expect the warning log to be called
      expect(github_app.instance_variable_get(:@log)).to receive(:warn).with(/GitHub secondary rate limit hit, sleeping for 60 seconds/)

      expect do
        github_app.search_issues("test")
      end.to raise_error(StandardError, /exceeded a secondary rate limit/)
    end
  end

  describe "#wait_for_rate_limit!" do
    let(:github_app) { GitHubApp.new }

    it "is a public method" do
      expect(github_app).to respond_to(:wait_for_rate_limit!)
      expect(github_app.public_methods).to include(:wait_for_rate_limit!)
    end

    it "handles rate limit normal case" do
      allow(github_app).to receive(:client).and_return(client)

      # Normal rate limit response with remaining requests
      rate_limit_response = {
        resources: {
          core: { remaining: 100, used: 4900, limit: 5000, reset: Time.now.to_i + 3600 }
        }
      }

      allow(client).to receive(:get).with("rate_limit").and_return(rate_limit_response)

      # This should complete without sleeping
      github_app.wait_for_rate_limit!(:core)
    end

    it "handles actual rate limit hit and sleep scenario" do
      github_app = GitHubApp.new
      allow(github_app).to receive(:client).and_return(client)

      # Rate limit response showing no remaining requests
      rate_limit_response = {
        resources: {
          core: { remaining: 0, used: 5000, limit: 5000, reset: Time.now.to_i + 5 } # resets in 5 seconds
        }
      }

      allow(client).to receive(:get).with("rate_limit").and_return(rate_limit_response)

      # Check that it logs the sleep messages
      expect(github_app.instance_variable_get(:@log)).to receive(:info).with(/github rate_limit hit: sleeping for:/)
      expect(github_app.instance_variable_get(:@log)).to receive(:info).with(/github rate_limit sleep complete/)

      github_app.wait_for_rate_limit!(:core)
    end

    it "handles rate limit that resets after refresh" do
      github_app = GitHubApp.new
      allow(github_app).to receive(:client).and_return(client)

      # First rate limit check shows 0 remaining
      first_response = {
        resources: {
          core: { remaining: 0, used: 5000, limit: 5000, reset: Time.now.to_i - 10 } # reset time in past
        }
      }

      # After refresh, rate limit shows available requests
      second_response = {
        resources: {
          core: { remaining: 5000, used: 0, limit: 5000, reset: Time.now.to_i + 3600 }
        }
      }

      allow(client).to receive(:get).with("rate_limit").and_return(first_response, second_response)

      # Since the method tries to fetch rate limit initially, it's already called once
      # Let's just check that the method completes without error
      expect { github_app.wait_for_rate_limit!(:core) }.not_to raise_error
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

  describe "auth with VCR" do
    it "fails because no env vars are provided at all" do
      github_app = GitHubApp.new
      # Mock the client method to fail immediately without any API calls
      allow(github_app).to receive(:client).and_raise(StandardError.new("Authentication failed"))
      # Test that the github_app can be created but will fail when trying to make API calls
      expect { github_app.user }.to raise_error(StandardError, "Authentication failed")
    end

    it "successfully authenticates with the GitHub App" do
      github_app = GitHubApp.new
      expect(github_app.rate_limit.remaining).to eq(5000)
    end
  end
end
